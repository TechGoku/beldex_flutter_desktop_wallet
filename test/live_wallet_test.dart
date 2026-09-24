// Live test against real beldex-wallet-rpc + a public node.
// Run with: BELDEX_BIN_DIR=/path/to/bin flutter test test/live_wallet_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:beldex_wallet/core/config.dart';
import 'package:beldex_wallet/services/daemon_service.dart';
import 'package:beldex_wallet/services/models.dart';
import 'package:beldex_wallet/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bin = Platform.environment['BELDEX_BIN_DIR'];
  test(
    'create, restore+sync, address book, send validation',
    () async {
      final tmp = await Directory.systemTemp.createTemp('bdx');
      final config = AppConfig.defaults()
        ..dataDir = '${tmp.path}/data'
        ..walletDataDir = '${tmp.path}/wallets'
        ..walletRpcPort = 29397;
      config.daemon
        ..type = DaemonType.remote
        ..remoteHost =
            'mainnet.beldex.io' // currently down: exercises failover
        ..remotePort = 29095;

      final daemon = DaemonService();
      final fallback = await daemon.findWorkingRemote(NetType.mainnet, exclude: 'mainnet.beldex.io');
      expect(fallback, isNotNull);
      config.daemon
        ..remoteHost = fallback!.host
        ..remotePort = fallback.port;
      await daemon.start(config);
      final wallet = WalletService(daemon);
      await wallet.start(config);
      try {
        final created = await wallet.createWallet('live1', 'pw', 'English');
        expect(wallet.isOpen, isTrue);
        expect(wallet.address, startsWith('bx'));
        expect(created.mnemonic.split(' ').length, 25);
        expect(await wallet.validateAddress(wallet.address), isTrue);
        expect(await wallet.validateAddress('bx${'1' * 95}'), isFalse);

        await expectLater(
          wallet.prepareTransfer(password: 'wrong', amount: 1, address: wallet.address, priority: 5),
          throwsA(isA<WalletException>().having((e) => e.i18nKey, 'key', 'notification.errors.invalidPassword')),
        );
        await expectLater(
          wallet.prepareTransfer(password: 'pw', amount: 1000000000, address: wallet.address, priority: 5),
          throwsA(isA<WalletException>()),
        );

        await wallet.saveAddressBookEntry(address: wallet.address, name: 'Me', description: 'test', starred: true);
        expect(wallet.addressBook.single.name, 'Me');
        expect(wallet.addressBook.single.starred, isTrue);

        final seed = created.mnemonic;
        await wallet.closeWallet();
        expect(wallet.isOpen, isFalse);

        while (daemon.info.height == 0) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
        final target = daemon.info.height;
        final sw = Stopwatch()..start();
        await wallet.restoreFromSeed('live2', 'pw', seed, target - 3000);
        while (wallet.height < daemon.info.height - 1) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (sw.elapsed > const Duration(minutes: 5)) fail('sync timeout');
        }
        // ignore: avoid_print
        print('restore 3000 blocks -> synced in ${sw.elapsedMilliseconds} ms (height ${wallet.height})');
        expect(wallet.address, startsWith('bx'));
        final list = await wallet.listWallets();
        expect(list.wallets.map((w) => w.name), containsAll(['live1', 'live2']));
      } finally {
        await wallet.stop();
        await daemon.stop();
        await tmp.delete(recursive: true);
      }
    },
    skip: bin == null ? 'set BELDEX_BIN_DIR to run' : false,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
