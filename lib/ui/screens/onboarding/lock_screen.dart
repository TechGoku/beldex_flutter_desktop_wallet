import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../kit.dart';
import '../../widgets/common.dart' show runWithProgress;

/// Shown when the UI is locked (manually or after inactivity). The wallet
/// stays open and keeps syncing underneath.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppController>().unlock(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Wrong password';
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.read<WalletService>();
    return BScaffold(
      body: Column560(
        maxWidth: 440,
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
        children: [
          const BrandMark(large: true),
          const SizedBox(height: 22),
          Center(child: H2(wallet.name)),
          const Center(child: Muted('Wallet locked', size: 12.5)),
          const SizedBox(height: 6),
          Center(child: Muted(shorten(wallet.address, head: 10, tail: 10), size: 11.5)),
          const SizedBox(height: 18),
          BCard(
            outlined: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Field(
                  controller: _password,
                  hint: 'Password',
                  obscure: true,
                  autofocus: true,
                  onSubmitted: (_) => _unlock(),
                ),
                PrimaryButton('Unlock', busy: _busy, onPressed: _unlock),
                ErrorText(_error),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GhostButton(
            'Switch wallet',
            onPressed: () async {
              final app = context.read<AppController>();
              await runWithProgress(context, wallet.closeWallet);
              app.userActivity();
            },
          ),
        ],
      ),
    );
  }
}
