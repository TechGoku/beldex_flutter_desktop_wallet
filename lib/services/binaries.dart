import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the bundled beldexd / beldex-wallet-rpc executables.
///
/// Search order: $BELDEX_BIN_DIR, `bin/` next to the app executable, the
/// app bundle's Resources/bin on macOS, `bin/` in the working directory,
/// then the PATH.
class Binaries {
  static String get _exe => Platform.isWindows ? '.exe' : '';

  static List<String> get searchDirs {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return [
      if (Platform.environment['BELDEX_BIN_DIR'] case final dir?) dir,
      p.join(exeDir, 'bin'),
      if (Platform.isMacOS) p.join(exeDir, '..', 'Resources', 'bin'),
      p.join(Directory.current.path, 'bin'),
      ...?Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':'),
    ];
  }

  static String? find(String name) {
    for (final dir in searchDirs) {
      final candidate = p.join(dir, '$name$_exe');
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static String? get daemon => find('beldexd');
  static String? get walletRpc => find('beldex-wallet-rpc');

  /// Returns `beldexd --version` output, or null if the binary is missing.
  static Future<String?> daemonVersion() async {
    final path = daemon;
    if (path == null) return null;
    try {
      final result = await Process.run(path, ['--version']);
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}

/// True when nothing is listening on [port] at [host].
Future<bool> isPortFree(int port, {String host = '127.0.0.1'}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 500));
    socket.destroy();
    return false;
  } catch (_) {
    return true;
  }
}
