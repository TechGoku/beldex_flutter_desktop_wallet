import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../state/app_controller.dart';
import '../kit.dart';
import '../theme.dart';
import 'settings/node_settings_form.dart';

/// First run: language + how to connect. Two clear choices instead of a
/// wall of node settings; everything else stays under "Advanced".
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final AppConfig _pending;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _pending = context.read<AppController>().config.copy();
    // Spread new users over the public nodes (the first one is often busy)
    final remote = knownRemotes[1 + Random().nextInt(knownRemotes.length - 1)];
    _pending.daemons[NetType.mainnet]!
      ..type = DaemonType.remote
      ..remoteHost = remote.host
      ..remotePort = remote.port;
  }

  void _choose(DaemonType type) => setState(() => _pending.daemon.type = type);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final locale = context.select<I18n, String>((i) => i.locale);
    final type = _pending.daemon.type;
    return BScaffold(
      body: Column560(
        maxWidth: 520,
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 30),
        children: [
          const BrandMark(large: true),
          const SizedBox(height: 18),
          Center(child: Text('WELCOME', style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: 6),
          const Muted('A private wallet for Beldex (BDX)', center: true),
          const SectionLabel('Language'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in languages)
                ChoiceChip(
                  label: Text(l.name),
                  selected: locale == l.code,
                  showCheckmark: false,
                  side: BorderSide(color: locale == l.code ? BeldexColors.green : BeldexColors.border),
                  onSelected: (_) {
                    _pending.language = l.code;
                    app.setLanguage(l.code);
                  },
                ),
            ],
          ),
          const SectionLabel('How do you want to connect?'),
          _Choice(
            selected: type == DaemonType.remote,
            icon: Icons.bolt,
            title: 'Public node (recommended)',
            body: 'Start in seconds. Your keys never leave this computer; a public node only serves blockchain data.',
            onTap: () => _choose(DaemonType.remote),
          ),
          const SizedBox(height: 8),
          _Choice(
            selected: type == DaemonType.localRemote,
            icon: Icons.sync_alt,
            title: 'My own node + public node while it syncs',
            body: 'Runs beldexd here for maximum privacy, and uses a public node until it has caught up.',
            onTap: () => _choose(DaemonType.localRemote),
          ),
          const SizedBox(height: 8),
          _Choice(
            selected: type == DaemonType.local,
            icon: Icons.storage,
            title: 'My own node only',
            body: 'Most private. The wallet can only be used after the full blockchain has downloaded.',
            onTap: () => _choose(DaemonType.local),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _advanced = !_advanced),
              child: Text(_advanced ? 'Hide advanced settings' : 'Advanced settings'),
            ),
          ),
          if (_advanced)
            BCard(
              child: NodeSettingsForm(config: _pending, onChanged: () => setState(() {})),
            ),
          const SizedBox(height: 18),
          PrimaryButton(
            'Continue',
            onPressed: () {
              _pending.language = locale;
              app.saveConfigAndStart(_pending);
            },
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.zero,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? BeldexColors.green.withValues(alpha: 0.07) : BeldexColors.card,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: selected ? BeldexColors.green : BeldexColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: selected ? BeldexColors.green : BeldexColors.muted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Muted(body, size: 11),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? BeldexColors.green : BeldexColors.muted,
          ),
        ],
      ),
    ),
  );
}
