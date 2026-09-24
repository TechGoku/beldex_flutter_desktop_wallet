import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../services/daemon_service.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText;
import '../settings/settings_screen.dart';
import 'add_wallet.dart';

/// Wallet picker + unlock (extension "Welcome back" screen).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  String? _selected;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  WalletFileInfo? _current(List<WalletFileInfo> wallets, String last) {
    if (wallets.isEmpty) return null;
    final name = _selected ?? last;
    return wallets.where((w) => w.name == name).firstOrNull ?? wallets.first;
  }

  Future<void> _unlock(WalletFileInfo w) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final wallet = context.read<WalletService>();
    final app = context.read<AppController>();
    try {
      await wallet.openWallet(w.name, _password.text);
      await app.rememberWallet(w.name);
      app.userActivity();
    } catch (e) {
      if (mounted) {
        final msg = errorText(e);
        setState(() => _error = msg.toLowerCase().contains('password') ? 'Wrong password' : msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = context.select<WalletService, List<WalletFileInfo>>((s) => s.walletList.wallets);
    final app = context.read<AppController>();
    final current = _current(wallets, app.config.lastWallet);

    // First run (no wallets yet): straight to onboarding
    if (current == null) return const AddWalletScreen(firstRun: true);

    final others = wallets.where((w) => w.name != current.name).toList();
    return BScaffold(
      body: Column(
        children: [
          Expanded(
            child: Column560(
              maxWidth: 440,
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
              children: [
                const BrandMark(large: true),
                const SizedBox(height: 22),
                Center(child: H2(current.name)),
                const Center(child: Muted('Unlock this wallet', size: 12.5)),
                const SizedBox(height: 8),
                Center(child: NetLabel(app.config.netType.name, warn: app.config.netType != NetType.mainnet)),
                if (current.address != null) ...[
                  const SizedBox(height: 8),
                  Center(child: Muted(shorten(current.address!, head: 10, tail: 10), size: 11.5)),
                ],
                const SizedBox(height: 18),
                BCard(
                  outlined: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Field(
                        controller: _password,
                        hint: current.passwordProtected == false ? 'No password set — press Unlock' : 'Password',
                        obscure: true,
                        autofocus: true,
                        onSubmitted: (_) => _unlock(current),
                      ),
                      PrimaryButton(_busy ? 'Unlocking…' : 'Unlock', busy: _busy, onPressed: () => _unlock(current)),
                      ErrorText(_error),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GhostButton(
                  '+ Add wallet',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddWalletScreen())),
                ),
                if (others.isNotEmpty) ...[
                  const SectionLabel('Other wallets'),
                  Column(
                    children: [
                      for (final w in others)
                        MenuRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: w.name,
                          subtitle: w.address == null ? null : shorten(w.address!, head: 8, tail: 8),
                          onTap: () => setState(() {
                            _selected = w.name;
                            _password.clear();
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const _NodeFooter(),
        ],
      ),
    );
  }
}

/// Connection status + node settings, bottom of the unlock screen.
class _NodeFooter extends StatelessWidget {
  const _NodeFooter();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final height = context.select<DaemonService, int>((d) => d.info.height);
    final d = app.config.daemon;
    final node = d.type == DaemonType.remote
        ? d.remoteHost
        : (d.type == DaemonType.local ? 'local node' : 'local + ${d.remoteHost}');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BeldexColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: height > 0 ? BeldexColors.green : BeldexColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Muted('$node · block ${height == 0 ? '…' : groupDigits(height)}', size: 11.5)),
          IconButton(
            tooltip: 'Node settings',
            icon: const Icon(Icons.settings_outlined, size: 18),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }
}
