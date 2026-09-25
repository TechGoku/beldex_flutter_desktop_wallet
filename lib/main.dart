import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'services/price_service.dart';
import 'services/swap/swap_service.dart';
import 'services/wallet_service.dart';
import 'state/app_controller.dart';
import 'ui/screens/home/home_screen.dart';
import 'ui/screens/onboarding/lock_screen.dart';
import 'ui/screens/onboarding/unlock_screen.dart';
import 'ui/screens/startup_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Unexpected errors are logged and the app carries on, instead of
  // unhandled async errors taking it down or a grey box replacing a screen.
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text('Something went wrong here. Try going back.', style: TextStyle(color: Color(0xFF8A8A8A))),
    ),
  );
  final app = AppController();
  runApp(BeldexWalletApp(controller: app));
  unawaited(app.boot());
}

class BeldexWalletApp extends StatefulWidget {
  const BeldexWalletApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<BeldexWalletApp> createState() => _BeldexWalletAppState();
}

class _BeldexWalletAppState extends State<BeldexWalletApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _prices = PriceService();
  StreamSubscription<AppNotice>? _notices;
  late final AppLifecycleListener _lifecycle;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _notices = widget.controller.notices.listen((n) {
      final context = _messengerKey.currentContext;
      if (context != null) showSnack(context, n.message, error: n.error, warning: n.warning);
    });
    // Stop wallet-rpc/beldexd cleanly when the window is closed
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.shutdown();
        return AppExitResponse.exit;
      },
    );
    ProcessSignal.sigint.watch().listen((_) async {
      await widget.controller.shutdown();
      exit(0);
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Any input restarts the auto-lock countdown (throttled).
  void _activity() {
    final now = DateTime.now();
    if (now.difference(_lastActivity) < const Duration(seconds: 5)) return;
    _lastActivity = now;
    widget.controller.userActivity();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.controller;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: app.daemon),
        ChangeNotifierProvider.value(value: app.wallet),
        ChangeNotifierProvider.value(value: I18n.instance),
        ChangeNotifierProvider.value(value: _prices),
        Provider(create: (_) => SwapService()),
      ],
      child: Listener(
        onPointerDown: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: Focus(
          onKeyEvent: (_, _) {
            _activity();
            return KeyEventResult.ignored;
          },
          child: Selector<I18n, String>(
            selector: (_, i) => i.locale,
            builder: (context, _, _) => MaterialApp(
              title: 'Beldex Wallet',
              debugShowCheckedModeBanner: false,
              scaffoldMessengerKey: _messengerKey,
              theme: buildTheme(),
              home: const _Root(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks the top-level screen from the startup stage and wallet state.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppController, StartupStage>((a) => a.stage);
    final locked = context.select<AppController, bool>((a) => a.locked);
    final walletOpen = context.select<WalletService, bool>((w) => w.isOpen);
    return switch (stage) {
      StartupStage.needsSetup => const WelcomeScreen(),
      StartupStage.ready when !walletOpen => const UnlockScreen(),
      StartupStage.ready when locked => const LockScreen(),
      StartupStage.ready => const HomeScreen(),
      _ => const StartupScreen(),
    };
  }
}
