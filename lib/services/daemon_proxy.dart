import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Scan position read from the node responses wallet-rpc receives.
class ScanProgress {
  const ScanProgress({required this.height, required this.target, required this.headersOnly});

  /// First block of the latest batch wallet-rpc received.
  final int height;

  /// Node height (0 if the response didn't say).
  final int target;

  /// True while wallet-rpc only fetches block hashes up to the restore
  /// height (fast, nothing is scanned yet).
  final bool headersOnly;
}

/// Local HTTP proxy that beldex-wallet-rpc uses as its node.
///
/// wallet-rpc refreshes on its only request thread and nothing can interrupt
/// it: once a scan starts, every call (store, close_wallet, getheight, …)
/// waits until the wallet has caught up. So closing mid-scan could not save
/// and all progress since the last save was lost.
///
/// Failing wallet-rpc's block-sync requests ends a running scan within a
/// fraction of a second, keeping everything scanned so far; other requests
/// (transfers, pool, json_rpc) always pass. The block responses also carry
/// the scan height, which gives live progress without asking wallet-rpc.
///
/// With [cacheDir] set, block-hash batches far below the chain tip (they can
/// no longer change) are kept on disk. A restore or rescan re-downloads the
/// whole hash list from the last checkpoint (~10 s); with the cache it is
/// served locally in well under a second.
class DaemonProxy {
  DaemonProxy({this.cacheDir});

  final String? cacheDir;
  static const _cacheLimitBytes = 100 * 1024 * 1024;

  HttpServer? _server;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);
  Uri _target = Uri(scheme: 'http', host: '127.0.0.1');
  bool _paused = false;
  final _inFlight = <HttpClientRequest>{};
  final _progress = StreamController<ScanProgress>.broadcast(sync: true);

  /// Requests that make up a wallet scan.
  static bool _isSync(String path) => path.endsWith('blocks.bin') || path.endsWith('hashes.bin');

  int get port => _server!.port;
  Stream<ScanProgress> get progress => _progress.stream;
  bool get paused => _paused;

  Future<void> start(String host, int port) async {
    setTarget(host, port);
    await _prepareCache();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  String get targetHost => _target.host;

  /// Points the proxy at another node; wallet-rpc doesn't need a restart.
  void setTarget(String host, int port) => _target = Uri(scheme: 'http', host: host, port: port);

  /// Fails block-sync requests (including ones in flight) until [resume].
  void pause() {
    _paused = true;
    for (final request in _inFlight.toList()) {
      request.abort();
    }
    _inFlight.clear();
  }

  void resume() => _paused = false;

  Future<void> close() async {
    pause();
    await _server?.close(force: true);
    _client.close(force: true);
    await _progress.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final sync = _isSync(path);
    final res = req.response;
    try {
      final body = await _readAll(req);
      if (sync && _paused) return await _reject(res);
      final cacheKey = cacheDir != null && path.endsWith('hashes.bin') ? _cacheKey(path, body) : null;
      if (cacheKey != null) {
        final cached = await _readCache(cacheKey);
        if (cached != null) {
          if (_paused) return await _reject(res);
          _observe(path, cached);
          res.headers.contentType = ContentType.binary;
          res.contentLength = cached.length;
          res.add(cached);
          return await res.close();
        }
      }
      final out = await _client.openUrl(req.method, _target.replace(path: path, query: req.uri.query));
      if (sync) _inFlight.add(out);
      try {
        final type = req.headers.contentType;
        if (type != null) out.headers.contentType = type;
        out.contentLength = body.length;
        out.add(body);
        final upstream = await out.close();
        final data = await _readAll(upstream);
        if (sync) {
          if (_paused) return await _reject(res);
          _observe(path, data);
          if (cacheKey != null && upstream.statusCode == 200 && _cacheable(data)) {
            unawaited(_writeCache(cacheKey, data));
          }
        }
        res.statusCode = upstream.statusCode;
        final ct = upstream.headers.contentType;
        if (ct != null) res.headers.contentType = ct;
        res.contentLength = data.length;
        res.add(data);
        await res.close();
      } finally {
        _inFlight.remove(out);
      }
    } catch (_) {
      await _reject(res);
    }
  }

  static Future<void> _reject(HttpResponse res) async {
    try {
      res.statusCode = HttpStatus.serviceUnavailable;
      res.contentLength = 0;
      await res.close();
    } catch (_) {
      // Headers already sent or the client went away
    }
  }

  static Future<Uint8List> _readAll(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  // ---- block-hash cache -----------------------------------------------------

  Future<void> _prepareCache() async {
    final dir = cacheDir;
    if (dir == null) return;
    try {
      final d = Directory(dir);
      await d.create(recursive: true);
      var size = 0;
      await for (final f in d.list()) {
        if (f is File) size += await f.length();
      }
      if (size > _cacheLimitBytes) {
        await d.delete(recursive: true);
        await d.create(recursive: true);
      }
    } catch (_) {
      // The cache is an optimisation only
    }
  }

  static String _cacheKey(String path, Uint8List body) => sha256.convert([...path.codeUnits, 0, ...body]).toString();

  Future<Uint8List?> _readCache(String key) async {
    try {
      final f = File(p.join(cacheDir!, '$key.bin'));
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, Uint8List data) async {
    try {
      final tmp = File(p.join(cacheDir!, '$key.tmp'));
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(p.join(cacheDir!, '$key.bin'));
    } catch (_) {
      // The cache is an optimisation only
    }
  }

  /// A successful batch whose hashes all lie far below the node's tip.
  /// Batches hold at most 10,000 hashes, so starting 20,000 below the tip
  /// leaves a wide margin for re-organisations.
  static bool _cacheable(Uint8List data) {
    final start = readEpeeUint64(data, 'start_height');
    final tip = readEpeeUint64(data, 'current_height');
    return start != null && tip != null && start + 20000 < tip && _statusOk(data);
  }

  /// `status: "OK"` in epee: name, type 10 (string), varint length 2 (0x08).
  static bool _statusOk(Uint8List data) {
    const pattern = [6, 115, 116, 97, 116, 117, 115, 10, 8, 79, 75]; // "status" "OK"
    for (var i = data.length - pattern.length; i >= 0; i--) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  void _observe(String path, Uint8List data) {
    final start = readEpeeUint64(data, 'start_height');
    if (start == null || _progress.isClosed) return;
    _progress.add(
      ScanProgress(
        height: start,
        target: readEpeeUint64(data, 'current_height') ?? 0,
        headersOnly: path.endsWith('hashes.bin'),
      ),
    );
  }
}

/// Reads a uint64 field named [key] from an epee portable-storage body (the
/// binary format of beldexd's `.bin` RPCs): a length-prefixed name, type 5
/// (uint64), then 8 little-endian bytes. Searches from the end because the
/// height fields follow the large block/hash arrays.
int? readEpeeUint64(Uint8List data, String key) {
  final pattern = [key.length, ...key.codeUnits, 5];
  for (var i = data.length - pattern.length - 8; i >= 0; i--) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return ByteData.sublistView(data, i + pattern.length, i + pattern.length + 8).getUint64(0, Endian.little);
    }
  }
  return null;
}
