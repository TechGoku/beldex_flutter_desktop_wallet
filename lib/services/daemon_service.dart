import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/config.dart';
import '../core/rpc_client.dart';
import 'binaries.dart';

class DaemonInfo {
  const DaemonInfo(this.raw);
  final Map<String, dynamic> raw;
  static const empty = DaemonInfo({});

  int get height => (raw['height'] as num?)?.toInt() ?? 0;
  int get targetHeight => (raw['target_height'] as num?)?.toInt() ?? 0;
  int get heightWithoutBootstrap => (raw['height_without_bootstrap'] as num?)?.toInt() ?? height;
  String get nettype => raw['nettype'] as String? ?? '';
  String? get version => raw['version'] as String?;
  int get incoming => (raw['incoming_connections_count'] as num?)?.toInt() ?? 0;
  int get outgoing => (raw['outgoing_connections_count'] as num?)?.toInt() ?? 0;
  int get txPoolSize => (raw['tx_pool_size'] as num?)?.toInt() ?? 0;
}

/// Manages beldexd (local process or remote node) and exposes its state.
class DaemonService extends ChangeNotifier {
  DaemonService();

  JsonRpcClient? _rpc;
  Process? _process;
  Timer? _heartbeat;
  Timer? _slowHeartbeat;
  Timer? _masterNodeHeartbeat;
  final _logSink = StringBuffer();

  bool local = false;
  DaemonInfo info = DaemonInfo.empty;
  List<Map<String, dynamic>> connections = const [];
  List<Map<String, dynamic>> bans = const [];
  List<Map<String, dynamic>> masterNodes = const [];
  bool masterNodesFetching = true;
  List<Map<String, dynamic>> blacklistedKeyImages = const [];

  String _lastInfoFingerprint = '';

  Uri _endpoint(String host, int port) => Uri.parse('http://$host:$port/json_rpc');

  /// Checks a remote node and returns its network type, or throws.
  Future<({String nettype, int height})> checkRemote(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = JsonRpcClient(endpoint: _endpoint(host, port));
    try {
      final r = await client.call('get_info', timeout: timeout);
      return (nettype: r['nettype'] as String? ?? '', height: (r['height'] as num?)?.toInt() ?? 0);
    } finally {
      client.close();
    }
  }

  /// Probes the known public nodes in parallel and returns the first healthy
  /// one on [net], or null if none answers.
  Future<RemoteNode?> findWorkingRemote(NetType net, {String? exclude}) async {
    final candidates = knownRemotes.where((r) => r.host != exclude).toList();
    if (candidates.isEmpty) return null;
    final completer = Completer<RemoteNode?>();
    var pending = candidates.length;
    for (final remote in candidates) {
      checkRemote(remote.host, remote.port, timeout: const Duration(seconds: 8))
          .then((r) {
            if (r.nettype == net.name && !completer.isCompleted) completer.complete(remote);
          })
          .catchError((_) {})
          .whenComplete(() {
            if (--pending == 0 && !completer.isCompleted) completer.complete(null);
          });
    }
    return completer.future;
  }

  /// Starts (or connects to) the daemon for [config]. Resolves once it
  /// answers RPC calls.
  Future<void> start(AppConfig config) async {
    final daemon = config.daemon;
    if (daemon.type == DaemonType.remote) {
      local = false;
      _rpc = JsonRpcClient(endpoint: _endpoint(daemon.remoteHost, daemon.remotePort), concurrency: 4);
      await _rpc!.call('get_info', timeout: const Duration(seconds: 20));
      _startHeartbeats();
      return;
    }

    local = true;
    if (daemon.rpcBindIp != '127.0.0.1') {
      throw StateError('Local daemon RPC must bind to 127.0.0.1 only.');
    }
    final binary = Binaries.daemon;
    if (binary == null) {
      throw StateError('beldexd not found. Please make sure your anti-virus has not removed it.');
    }
    if (!await isPortFree(daemon.rpcBindPort)) {
      throw StateError('Local daemon port ${daemon.rpcBindPort} is in use');
    }

    await Directory(config.logDir).create(recursive: true);
    final args = [
      '--data-dir',
      config.dataDir,
      '--p2p-bind-ip',
      daemon.p2pBindIp,
      '--p2p-bind-port',
      '${daemon.p2pBindPort}',
      '--rpc-bind-ip',
      daemon.rpcBindIp,
      '--rpc-bind-port',
      '${daemon.rpcBindPort}',
      '--out-peers',
      '${daemon.outPeers}',
      '--in-peers',
      '${daemon.inPeers}',
      '--limit-rate-up',
      '${daemon.limitRateUp}',
      '--limit-rate-down',
      '${daemon.limitRateDown}',
      '--log-level',
      '${daemon.logLevel}',
      '--log-file',
      p.join(config.logDir, 'beldexd.log'),
      if (config.netType == NetType.testnet) '--testnet',
      if (config.netType == NetType.stagenet) '--stagenet',
      if (daemon.type == DaemonType.localRemote && config.netType == NetType.mainnet) ...[
        '--bootstrap-daemon-address',
        '${daemon.remoteHost}:${daemon.remotePort}',
      ],
    ];

    _rpc = JsonRpcClient(endpoint: _endpoint(daemon.rpcBindIp, daemon.rpcBindPort), concurrency: 4);
    _process = await Process.start(binary, args);
    final exited = Completer<int>();
    _process!.exitCode.then((code) {
      _process = null;
      if (!exited.isCompleted) exited.complete(code);
    });
    _process!.stdout.transform(utf8.decoder).listen(_appendLog);
    _process!.stderr.transform(utf8.decoder).listen(_appendLog);

    // Wait until the RPC answers. No overall timeout: a local daemon may be
    // busy loading the database.
    while (true) {
      if (exited.isCompleted) {
        throw StateError('Failed to start local daemon (exit code ${await exited.future})');
      }
      try {
        await _rpc!.call('get_info', timeout: const Duration(seconds: 5));
        break;
      } on RpcError catch (e) {
        if (!e.isConnectionRefused && e.code != -1) rethrow;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    _startHeartbeats();
  }

  void _appendLog(String data) {
    if (_logSink.length > 20000) _logSink.clear();
    _logSink.write(data);
  }

  String get recentLog => _logSink.toString();

  void _startHeartbeats() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(Duration(seconds: local ? 5 : 15), (_) => _refreshInfo());
    _refreshInfo();

    _slowHeartbeat?.cancel();
    if (local) {
      _slowHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) => refreshPeers());
      refreshPeers();
    }

    _masterNodeHeartbeat?.cancel();
    _masterNodeHeartbeat = Timer.periodic(const Duration(minutes: 5), (_) => refreshMasterNodes());
    refreshMasterNodes();
  }

  Future<void> _refreshInfo() async {
    try {
      final r = await _rpc!.call('get_info', timeout: const Duration(seconds: 10));
      // Only rebuild listeners when something actually changed
      final fingerprint =
          '${r['height']}|${r['target_height']}|${r['height_without_bootstrap']}|'
          '${r['incoming_connections_count']}|${r['outgoing_connections_count']}|${r['tx_pool_size']}';
      if (fingerprint == _lastInfoFingerprint) return;
      _lastInfoFingerprint = fingerprint;
      info = DaemonInfo(r);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshPeers() async {
    try {
      final results = await Future.wait([_rpc!.call('get_connections'), _rpc!.call('get_bans')]);
      connections = ((results[0]['connections'] as List?) ?? const []).cast<Map<String, dynamic>>();
      bans = ((results[1]['bans'] as List?) ?? const []).cast<Map<String, dynamic>>();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshMasterNodes() async {
    masterNodesFetching = true;
    notifyListeners();
    try {
      final r = await _rpc!.call('get_master_nodes', timeout: const Duration(seconds: 60));
      masterNodes = ((r['master_node_states'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {}
    try {
      final r = await _rpc!.call('get_master_node_blacklisted_key_images');
      blacklistedKeyImages = ((r['blacklist'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {}
    masterNodesFetching = false;
    notifyListeners();
  }

  Future<void> banPeer(String host, int seconds) async {
    await _rpc!.call(
      'set_bans',
      params: {
        'bans': [
          {'host': host, 'seconds': seconds, 'ban': true},
        ],
      },
    );
    await refreshPeers();
  }

  /// Owners -> BNS records (max 256 owners per call).
  Future<List<Map<String, dynamic>>> bnsRecordsForOwners(List<String> owners) async {
    if (owners.isEmpty) return const [];
    final limited = owners.take(256).toList();
    final r = await _rpc!.call('bns_owners_to_names', params: {'entries': limited});
    final entries = ((r['entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return [
      for (final e in entries) {...e, 'owner': limited[(e['request_index'] as num).toInt()]},
    ];
  }

  Future<Map<String, dynamic>?> bnsRecord(String nameHash) async {
    final r = await _rpc!.call(
      'bns_names_to_owners',
      params: {
        'name_hash': [nameHash],
      },
    );
    final entries = (r['result'] as List?) ?? (r['entries'] as List?) ?? const [];
    return entries.isEmpty ? null : (entries.first as Map).cast<String, dynamic>();
  }

  /// Estimates the block height at [timestamp] (seconds), refining the guess
  /// against real block headers. Returns null when it can't be determined.
  Future<int?> timestampToHeight(int timestamp) async {
    const blockTime = 120;
    var pivotHeight = 119681;
    var pivotTime = 1539676273;
    for (var i = 0; i < 10; i++) {
      final estimate = pivotHeight + (timestamp - pivotTime) ~/ blockTime;
      if (estimate <= 0) return 0;
      Map<String, dynamic> header;
      try {
        final r = await _rpc!.call('get_block_header_by_height', params: {'height': estimate});
        header = (r['block_header'] as Map).cast<String, dynamic>();
      } on RpcError catch (e) {
        if (e.code != -2) return null;
        // Too high: pivot on the chain tip instead
        final r = await _rpc!.call('get_last_block_header');
        header = (r['block_header'] as Map).cast<String, dynamic>();
      }
      pivotHeight = (header['height'] as num).toInt();
      pivotTime = (header['timestamp'] as num).toInt();
      if ((timestamp - pivotTime).abs() < 3600) return pivotHeight;
    }
    return pivotHeight;
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _slowHeartbeat?.cancel();
    _masterNodeHeartbeat?.cancel();
    final proc = _process;
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    _rpc?.close();
  }
}
