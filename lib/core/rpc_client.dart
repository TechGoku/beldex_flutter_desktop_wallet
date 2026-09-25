import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Error returned by a JSON-RPC call (or a transport failure, code -1).
class RpcError implements Exception {
  RpcError(this.code, this.message, {this.cause});
  final int code;
  final String message;
  final Object? cause;

  bool get isConnectionRefused =>
      cause is SocketException &&
      ((cause as SocketException).osError?.errorCode == 111 || (cause as SocketException).message.contains('refused'));

  /// Message with the first letter capitalised, as the Electron UI shows it.
  String get displayMessage => message.isEmpty ? message : message[0].toUpperCase() + message.substring(1);

  @override
  String toString() => 'RpcError($code): $message';
}

/// Runs async tasks with bounded concurrency, in submission order.
class TaskQueue {
  TaskQueue(this.concurrency);
  final int concurrency;
  int _running = 0;
  final _waiting = Queue<void Function()>();

  Future<T> add<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    void run() {
      _running++;
      task().then(completer.complete, onError: completer.completeError).whenComplete(() {
        _running--;
        if (_waiting.isNotEmpty) _waiting.removeFirst()();
      });
    }

    if (_running < concurrency) {
      run();
    } else {
      _waiting.add(run);
    }
    return completer.future;
  }
}

/// JSON-RPC 2.0 over HTTP, used for both beldexd and beldex-wallet-rpc.
class JsonRpcClient {
  JsonRpcClient({required this.endpoint, this.username, this.password, int concurrency = 1})
    : _queue = TaskQueue(concurrency);

  Uri endpoint;
  final String? username;
  final String? password;
  final TaskQueue _queue;
  final http.Client _http = http.Client();
  int _id = 0;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (username != null)
      // beldex-wallet-rpc v7 uses HTTP Basic auth for --rpc-login
      'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  /// Calls [method]; throws [RpcError] on RPC or transport errors.
  /// [timeout] starts when the request is actually sent, not when queued.
  /// [closeConnection] closes the connection after the reply instead of
  /// keeping it for reuse.
  Future<Map<String, dynamic>> call(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
    Uri? endpointOverride,
    bool closeConnection = false,
  }) {
    return _queue.add(() => _send(method, params, timeout, endpointOverride, closeConnection));
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Map<String, dynamic>? params,
    Duration? timeout,
    Uri? endpointOverride,
    bool closeConnection,
  ) async {
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': '${_id++}',
      'method': method,
      if (params != null && params.isNotEmpty) 'params': params,
    };
    http.Response response;
    try {
      var request = _http.post(
        endpointOverride ?? endpoint,
        headers: {..._headers, if (closeConnection) 'Connection': 'close'},
        body: jsonEncode(body),
      );
      if (timeout != null) request = request.timeout(timeout);
      response = await request;
    } on TimeoutException catch (e) {
      throw RpcError(-1, 'Request timed out', cause: e);
    } catch (e) {
      throw RpcError(-1, 'Cannot connect to RPC server', cause: e);
    }

    if (response.statusCode == 401) {
      throw RpcError(-1, 'RPC authentication failed');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw RpcError(-1, 'Invalid RPC response (HTTP ${response.statusCode})', cause: e);
    }
    final error = decoded['error'];
    if (error is Map) {
      throw RpcError((error['code'] as num?)?.toInt() ?? -1, '${error['message'] ?? 'Unknown error'}');
    }
    final result = decoded['result'];
    return result is Map<String, dynamic> ? result : <String, dynamic>{};
  }

  void close() => _http.close();
}
