import 'dart:typed_data';

import 'package:beldex_wallet/core/config.dart';
import 'package:beldex_wallet/core/format.dart';
import 'package:beldex_wallet/core/password_hash.dart';
import 'package:beldex_wallet/core/validators.dart';
import 'package:beldex_wallet/services/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBdx is exact and rejects bad input', () {
    expect(parseBdx('1'), 1000000000);
    expect(parseBdx('0.1'), 100000000);
    expect(parseBdx('12.123456789'), 12123456789);
    expect(parseBdx('.5'), 500000000);
    expect(parseBdx('1.0000000001'), isNull);
    expect(parseBdx('abc'), isNull);
    expect(parseBdx(''), isNull);
  });

  test('formatBdx', () {
    expect(formatBdx(1234500000000), '1,234.5');
    expect(formatBdx(1, round: true), '0.0000');
  });

  test('address book description encoding round-trips', () {
    final enc = AddressBookEntry.encodeDescription('Alice', 'rent', true);
    expect(enc, 'starred::Alice::rent');
    final e = AddressBookEntry.fromRpc({'index': 3, 'address': 'bx1', 'description': enc});
    expect((e.name, e.description, e.starred), ('Alice', 'rent', true));
    expect(AddressBookEntry.fromRpc({'index': 0, 'address': 'a', 'description': 'Bob'}).name, 'Bob');
  });

  test('validators', () {
    expect(isHex64('a' * 64), isTrue);
    expect(isBnsName('my-name'), isTrue);
    expect(isBnsName('-bad'), isFalse);
    expect(isValidSeedLength(List.filled(25, 'w').join(' ')), isTrue);
    expect(isValidSeedLength('one two'), isFalse);
    expect(isEthAddress('0x${'a' * 40}'), isTrue);
  });

  test('config JSON round-trip keeps daemon settings', () {
    final c = AppConfig.defaults()
      ..netType = NetType.testnet
      ..daemons[NetType.mainnet]!.remoteHost = 'node.example';
    final back = AppConfig.fromJson(c.toJson());
    expect(back.netType, NetType.testnet);
    expect(back.daemons[NetType.mainnet]!.remoteHost, 'node.example');
    expect(back.walletDir, endsWith('testnet/wallets'));
  });

  test('pbkdf2 matches RFC 7914 test vector (sha256)', () {
    final out = pbkdf2('passwd', Uint8List.fromList('salt'.codeUnits), 1);
    expect(out.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), '55ac046e56e3089f');
  });

  test('password hasher verifies in a background isolate', () async {
    final h = PasswordHasher();
    await h.remember('secret');
    expect(await h.verify('secret'), isTrue);
    expect(await h.verify('wrong'), isFalse);
    expect(await h.hasPassword(), isTrue);
  });

  test('transfer classification', () {
    expect(Transfer({'type': 'pool', 'height': 0}).isPending, isTrue);
    expect(Transfer({'type': 'in', 'height': 10}).isPending, isFalse);
    expect(Transfer({'type': 'mnode', 'height': 10}).isIncoming, isTrue);
  });
}
