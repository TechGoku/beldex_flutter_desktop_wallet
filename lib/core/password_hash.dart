import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Keeps a salted PBKDF2 hash of the open wallet's password so sensitive
/// actions (send, stake, show keys, ...) can re-confirm the password without
/// holding it in memory. Hashing runs in a background isolate so the UI
/// never stalls.
class PasswordHasher {
  PasswordHasher() : _salt = _randomBytes(32);

  static const _iterations = 200000;
  final Uint8List _salt;
  Future<Uint8List>? _hash;

  bool get hasHash => _hash != null;

  /// Starts hashing [password] in the background, so opening a wallet
  /// doesn't wait for it; [verify] waits if it hasn't finished yet.
  void remember(String password) {
    final pending = _derive(password, _salt);
    pending.ignore(); // errors surface in verify()
    _hash = pending;
  }

  void forget() => _hash = null;

  Future<bool> verify(String password) async {
    final pending = _hash;
    if (pending == null) return true;
    final stored = await pending;
    final candidate = await _derive(password, _salt);
    // Constant-time comparison
    var diff = 0;
    for (var i = 0; i < stored.length; i++) {
      diff |= stored[i] ^ candidate[i];
    }
    return diff == 0;
  }

  /// True when the wallet was opened with a non-empty password.
  Future<bool> hasPassword() async => _hash != null && !(await verify(''));

  static Future<Uint8List> _derive(String password, Uint8List salt) =>
      Isolate.run(() => pbkdf2(password, salt, _iterations));

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}

Uint8List pbkdf2(String password, Uint8List salt, int iterations) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

/// Random hex string for RPC credentials.
String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
