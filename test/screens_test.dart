// Renders the main screens to PNG with real fonts and sample data:
//   flutter test test/screens_test.dart --update-goldens
// Output: test/screens/*.png
@Tags(['screens'])
library;

import 'dart:io';

import 'package:beldex_wallet/core/config.dart';
import 'package:beldex_wallet/core/i18n.dart';
import 'package:beldex_wallet/services/daemon_service.dart';
import 'package:beldex_wallet/services/models.dart';
import 'package:beldex_wallet/services/price_service.dart';
import 'package:beldex_wallet/services/swap/swap_service.dart';
import 'package:beldex_wallet/state/app_controller.dart';
import 'package:beldex_wallet/ui/screens/home/home_screen.dart';
import 'package:beldex_wallet/ui/screens/onboarding/add_wallet.dart';
import 'package:beldex_wallet/ui/screens/onboarding/lock_screen.dart';
import 'package:beldex_wallet/ui/screens/onboarding/unlock_screen.dart';
import 'package:beldex_wallet/ui/screens/welcome_screen.dart';
import 'package:beldex_wallet/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

const _addr = 'bxdA5xztdQjWo1Kx8QkSsVJ5P5eK4Wj3pd1sEAhgBBvbSjvP9CzYzsHGVDmAAgj8SJ1MPHd7G6Y3vYRVyXLGu4Tb2qVs5YQ8m';

AppController _app() {
  final app = AppController();
  app.config = AppConfig.defaults()
    ..lastWallet = 'Savings'
    ..daemons[NetType.mainnet]!.remoteHost = 'publicnode1.rpcnode.stream';
  app.stage = StartupStage.ready;
  final w = app.wallet
    ..isOpen = true
    ..name = 'Savings'
    ..address = _addr
    ..height = 5774902
    ..debugMarkSynced()
    ..balance = 1284500000000
    ..unlockedBalance = 1204500000000
    ..walletList = WalletList(
      wallets: [
        WalletFileInfo(name: 'Savings', address: _addr),
        WalletFileInfo(
          name: 'Mining',
          address: 'bxc2oKaQfh4aHWcfk5h4QwctmdcAqLoiBco4hoz5gH4cMvGWgjkE9SYTYsHsRA${'x' * 35}',
        ),
        WalletFileInfo(name: 'Cold storage', address: 'bxcS9ZMSg3z7${'y' * 85}'),
      ],
    )
    ..addressBook = [
      AddressBookEntry(index: 0, address: 'bxcS9ZMSg3z7${'y' * 85}', name: 'Alice', description: 'rent', starred: true),
      AddressBookEntry(index: 1, address: 'bxc6ZdVw3xVc${'z' * 85}', name: 'Exchange', description: '', starred: false),
    ];
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  Transfer tx(String type, int amount, int ago, int height, {String note = '', int fee = 0}) => Transfer({
    'txid': '${type.hashCode.toRadixString(16)}${ago.toRadixString(16)}'.padRight(64, 'a'),
    'type': type,
    'amount': amount,
    'fee': fee,
    'height': height,
    'timestamp': now - ago,
    'note': note,
    'confirmations': height == 0 ? 0 : 5774902 - height,
  });
  w.transfers = [
    tx('pool', 25000000000, 40, 0),
    tx('in', 150000000000, 3600 * 3, 5774500, note: 'Invoice #42'),
    tx('out', 42000000000, 3600 * 20, 5773900, fee: 21000000),
    tx('mnode', 1850000000, 86400 * 2, 5770200),
    tx('stake', 1000000000000, 86400 * 9, 5750000),
    tx('in', 500000000000, 86400 * 30, 5700000),
  ];
  return app;
}

final _shotKey = GlobalKey();

Widget _wrap(AppController app, Widget child) {
  final prices = PriceService()..usd = 0.0612;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider<DaemonService>.value(value: app.daemon),
      ChangeNotifierProvider.value(value: app.wallet),
      ChangeNotifierProvider.value(value: I18n.instance),
      ChangeNotifierProvider.value(value: prices),
      Provider(create: (_) => SwapService()),
    ],
    child: RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: child),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont('Michroma', ['assets/fonts/Michroma-Regular.ttf']);
    await _loadFont('SpaceMono', ['assets/fonts/SpaceMono-Regular.ttf', 'assets/fonts/SpaceMono-Bold.ttf']);
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/sdk/flutter';
    await _loadFont('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    await I18n.instance.load('en-us');
  });

  Future<void> shot(WidgetTester tester, String name, Widget screen, {Future<void> Function(WidgetTester)? act}) async {
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1.0;
    final app = _app();
    app.daemon.info = const DaemonInfo({'height': 5774904, 'target_height': 5774904});
    await tester.pumpWidget(_wrap(app, screen));
    await tester.pump(const Duration(milliseconds: 400));
    if (act != null) {
      await act(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    await expectLater(find.byKey(_shotKey), matchesGoldenFile('screens/$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('home', (t) => shot(t, 'home', const HomeScreen()));
  testWidgets(
    'send',
    (t) => shot(
      t,
      'send',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Send').first);
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets(
    'receive',
    (t) => shot(
      t,
      'receive',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Receive').first);
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets(
    'settings',
    (t) => shot(
      t,
      'settings',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Settings'));
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets(
    'tx details',
    (t) => shot(
      t,
      'tx_details',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Invoice #42'));
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets(
    'transactions',
    (t) => shot(
      t,
      'transactions',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Transactions'));
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets(
    'contacts',
    (t) => shot(
      t,
      'contacts',
      const HomeScreen(),
      act: (t) async {
        await t.tap(find.text('Contacts'));
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
  testWidgets('unlock', (t) => shot(t, 'unlock', const UnlockScreen()));
  testWidgets('lock', (t) => shot(t, 'lock', const LockScreen()));
  testWidgets('welcome', (t) => shot(t, 'welcome', const WelcomeScreen()));
  testWidgets('add wallet', (t) => shot(t, 'add_wallet', const AddWalletScreen()));
}
