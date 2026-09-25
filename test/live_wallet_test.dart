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

  Future<(DaemonService, WalletService, Directory)> boot(int port) async {
    final tmp = await Directory.systemTemp.createTemp('bdx');
    final config = AppConfig.defaults()
      ..dataDir = '${tmp.path}/data'
      ..walletDataDir = '${tmp.path}/wallets'
      ..walletRpcPort = port;
    final daemon = DaemonService();
    final node = await daemon.findWorkingRemote(NetType.mainnet, exclude: 'mainnet.beldex.io');
    expect(node, isNotNull);
    config.daemon
      ..type = DaemonType.remote
      ..remoteHost = node!.host
      ..remotePort = node.port;
    await daemon.start(config);
    final wallet = WalletService(daemon);
    await wallet.start(config);
    while (daemon.info.height == 0) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return (daemon, wallet, tmp);
  }

  Future<void> waitFor(bool Function() done, Duration limit, String what) async {
    final sw = Stopwatch()..start();
    while (!done()) {
      if (sw.elapsed > limit) fail('timed out waiting for $what');
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  test(
    'closing mid-scan saves progress; reopen resumes; rescan from height resumes too',
    () async {
      final (daemon, wallet, tmp) = await boot(29398);
      try {
        final seed = (await wallet.createWallet('src', 'pw', 'English')).mnemonic;
        await wallet.closeWallet();

        final tip = daemon.info.height;
        final restoreHeight = tip - 40000;
        await wallet.restoreFromSeed('resume', 'pw', seed, restoreHeight);

        // Live progress while scanning, in batch-sized steps
        final seen = <int>{};
        void sample() {
          if (wallet.syncStatus.phase == SyncPhase.scanning) seen.add(wallet.height);
        }

        wallet.addListener(sample);
        await waitFor(() => wallet.height > restoreHeight + 8000, const Duration(minutes: 4), 'scan progress');
        wallet.removeListener(sample);
        expect(seen.length, greaterThan(5), reason: 'progress should update per batch');

        // A user call while scanning is answered at once (the chunk ends early)
        final call = Stopwatch()..start();
        expect(await wallet.validateAddress(wallet.address), isTrue);
        // ignore: avoid_print
        print('validate_address during scan: ${call.elapsedMilliseconds} ms');
        expect(call.elapsed, lessThan(const Duration(seconds: 5)));

        final before = wallet.height;
        final close = Stopwatch()..start();
        await wallet.closeWallet();
        // ignore: avoid_print
        print('closed mid-scan at ~$before in ${close.elapsedMilliseconds} ms');
        expect(close.elapsed, lessThan(const Duration(seconds: 8)));

        await wallet.openWallet('resume', 'pw');
        final resumedAt = wallet.height;
        // ignore: avoid_print
        print('reopened at $resumedAt (restore height $restoreHeight, closed at ~$before)');
        expect(resumedAt, greaterThan(restoreHeight + 6000), reason: 'progress must survive a close mid-scan');

        final sync = Stopwatch()..start();
        await waitFor(() => wallet.syncStatus.phase == SyncPhase.synced, const Duration(minutes: 6), 'sync');
        // ignore: avoid_print
        print('finished remaining ${tip - resumedAt} blocks in ${sync.elapsed.inSeconds} s');

        // Rescan from a height above the restore height, closing midway: blocks
        // below the height are skipped, and after reopening the rescan carries
        // on from where it stopped. (wallet2 never scans below the wallet's own
        // restore height, so that is the useful range.)
        final from = restoreHeight + 10000;
        final rescan = Stopwatch()..start();
        await wallet.rescanBlockchain(fromHeight: from);
        final skipped = <int>{};
        void track() {
          final h = wallet.height;
          if (wallet.syncStatus.phase == SyncPhase.scanning && h > restoreHeight + 500 && h < from - 500)
            skipped.add(h);
        }

        wallet.addListener(track);
        await waitFor(
          () => wallet.syncStatus.phase == SyncPhase.scanning && wallet.height > from + 1500,
          const Duration(minutes: 3),
          'rescan progress',
        );
        final closedAt = wallet.height;
        await wallet.closeWallet();
        await wallet.openWallet('resume', 'pw');
        // ignore: avoid_print
        print('rescan from $from: closed at ~$closedAt, reopened at ${wallet.height} (restore height $restoreHeight)');
        expect(wallet.height, greaterThanOrEqualTo(from), reason: 'the rescan must resume, not restart');
        await waitFor(() => wallet.syncStatus.phase == SyncPhase.synced, const Duration(minutes: 6), 'rescan');
        wallet.removeListener(track);
        // ignore: avoid_print
        print(
          'rescan of ${daemon.info.height - from} blocks (with a close/reopen) done in ${rescan.elapsed.inSeconds} s',
        );
        expect(skipped, isEmpty, reason: 'blocks below the rescan height must be skipped');
        expect(wallet.height, greaterThanOrEqualTo(daemon.info.height - 3));
      } finally {
        final quit = Stopwatch()..start();
        await wallet.stop();
        // ignore: avoid_print
        print('wallet.stop() (close + wallet-rpc exit) took ${quit.elapsedMilliseconds} ms');
        await daemon.stop();
        await tmp.delete(recursive: true);
      }
    },
    skip: bin == null ? 'set BELDEX_BIN_DIR to run' : false,
    timeout: const Timeout(Duration(minutes: 15)),
  );

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
