import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/i18n.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText, showSnack;
import '../settings/settings_screen.dart';
import 'home_screen.dart';

class WalletSettingsView extends StatelessWidget {
  const WalletSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final wallet = context.read<WalletService>();
    final c = app.config;
    final language = languages.where((l) => l.code == c.language).firstOrNull?.name ?? c.language;

    final home = HomeScreen.of(context);
    final net = c.netType;
    final lock = c.autoLockMinutes == 0
        ? 'never'
        : (c.autoLockMinutes >= 60 ? '${c.autoLockMinutes ~/ 60}h' : '${c.autoLockMinutes}m');

    Widget group(String title, List<Widget> rows) => Panel(
      title: title,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(children: rows),
    );

    final left = [
      group('Network', [
        MenuRow(
          icon: Icons.language_outlined,
          label: 'Node & network',
          subtitle: nodeLabel(c.daemon),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NetLabel(net.name, warn: net != NetType.mainnet),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: BeldexColors.muted),
            ],
          ),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ]),
      group('Preferences', [
        MenuRow(icon: Icons.timer_outlined, label: 'Auto-lock', subtitle: lock, onTap: () => _autoLock(context)),
        MenuRow(
          icon: Icons.visibility_off_outlined,
          label: 'Hide balances',
          trailing: SquareSwitch(
            value: c.hideBalance,
            onChanged: (v) => app.updatePreferences((c) => c.hideBalance = v),
          ),
          onTap: () => app.updatePreferences((c) => c.hideBalance = !c.hideBalance),
        ),
        MenuRow(
          icon: Icons.attach_money,
          label: 'Show USD value',
          subtitle: 'Price from CoinGecko',
          trailing: SquareSwitch(value: c.showFiat, onChanged: (v) => app.updatePreferences((c) => c.showFiat = v)),
          onTap: () => app.updatePreferences((c) => c.showFiat = !c.showFiat),
        ),
        MenuRow(
          icon: Icons.verified_user_outlined,
          label: 'Ask for password on every send',
          trailing: SquareSwitch(
            value: c.askPasswordOnSend,
            onChanged: (v) => app.updatePreferences((c) => c.askPasswordOnSend = v),
          ),
          onTap: () => app.updatePreferences((c) => c.askPasswordOnSend = !c.askPasswordOnSend),
        ),
        MenuRow(icon: Icons.translate, label: 'Language', subtitle: language, onTap: () => _language(context)),
      ]),
      group('Tools', [
        MenuRow(
          icon: Icons.sync,
          label: 'Rescan',
          subtitle: 'Fix a wrong balance or missing transactions',
          onTap: () => _rescan(context),
        ),
        MenuRow(
          icon: Icons.import_export,
          label: 'Key images',
          subtitle: 'Export / import for view-only wallets',
          onTap: () => _keyImages(context),
        ),
      ]),
    ];
    final right = [
      group('Security', [
        MenuRow(
          icon: Icons.format_list_numbered,
          label: 'Show recovery seed',
          onTap: () => _reveal(context, _Secret.seed),
        ),
        MenuRow(
          icon: Icons.visibility_outlined,
          label: 'Show private view key',
          onTap: () => _reveal(context, _Secret.view),
        ),
        if (!wallet.viewOnly)
          MenuRow(
            icon: Icons.key_outlined,
            label: 'Show private spend key',
            onTap: () => _reveal(context, _Secret.spend),
          ),
        MenuRow(icon: Icons.password, label: 'Change password', onTap: () => _changePassword(context)),
      ]),
      group('Register', [
        MenuRow(
          icon: Icons.dns_outlined,
          label: 'Register master node',
          onTap: wallet.viewOnly ? null : () => home?.registerMasterNode(),
        ),
        MenuRow(
          icon: Icons.alternate_email,
          label: 'Register BNS name',
          onTap: wallet.viewOnly ? null : () => home?.show(HomeView.bns),
        ),
      ]),
      group('Wallet', [
        MenuRow(icon: Icons.lock_outline, label: 'Lock now', subtitle: 'Ctrl+L', onTap: app.lock),
        MenuRow(
          icon: Icons.help_outline,
          label: 'Support',
          subtitle: 'beldex.io',
          trailing: const Icon(Icons.open_in_new, size: 16, color: BeldexColors.muted),
          onTap: () => launchUrl(Uri.parse('https://beldex.io/')),
        ),
        MenuRow(icon: Icons.delete_outline, label: 'Delete wallet', danger: true, onTap: () => _delete(context)),
      ]),
    ];

    Widget stack(List<Widget> panels) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in panels.indexed) ...[if (i > 0) const SizedBox(height: 16), p],
      ],
    );

    return ResponsiveRow(breakpoint: 820, children: [stack(left), stack(right)]);
  }

  Future<void> _autoLock(BuildContext context) async {
    final app = context.read<AppController>();
    await showBModal<void>(
      context,
      width: 360,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const H2('Auto-Lock'),
          const Muted('Lock the wallet after this much inactivity.'),
          const SizedBox(height: 10),
          for (final (m, label) in [
            (5, '5 minutes'),
            (15, '15 minutes'),
            (30, '30 minutes'),
            (60, '1 hour'),
            (0, 'Never'),
          ])
            MenuRow(
              label: label,
              trailing: m == app.config.autoLockMinutes
                  ? const Icon(Icons.check, color: BeldexColors.green, size: 18)
                  : const SizedBox.shrink(),
              onTap: () {
                app.updatePreferences((c) => c.autoLockMinutes = m);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _reveal(BuildContext context, _Secret kind) =>
      showBModal<void>(context, dismissible: false, width: 460, builder: (_) => _RevealSecret(kind: kind));

  Future<void> _language(BuildContext context) async {
    final app = context.read<AppController>();
    await showBModal<void>(
      context,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Language'),
            for (final l in languages)
              MenuRow(
                label: l.name,
                trailing: l.code == app.config.language
                    ? const Icon(Icons.check, color: BeldexColors.green, size: 18)
                    : const SizedBox.shrink(),
                onTap: () {
                  app.setLanguage(l.code);
                  Navigator.pop(ctx);
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final wallet = context.read<WalletService>();
    final old = TextEditingController(), next = TextEditingController(), confirm = TextEditingController();
    String? error, ok;
    await showBModal<void>(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const H2('Change password'),
                Field(controller: old, hint: 'Current password', obscure: true, autofocus: true),
                Field(
                  controller: next,
                  hint: 'New password (min 8 characters)',
                  obscure: true,
                  onChanged: (_) => setState(() {}),
                ),
                StrengthMeter(next.text),
                Field(controller: confirm, hint: 'Confirm new password', obscure: true),
                if (ok != null) IconLabel(Icons.check, ok!, color: BeldexColors.green, size: 11.5),
                ErrorText(error),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: GhostButton('Close', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        'Change',
                        onPressed: () async {
                          setState(() {
                            error = null;
                            ok = null;
                          });
                          if (next.text.length < 8)
                            return setState(() => error = 'New password must be at least 8 characters');
                          if (next.text != confirm.text) return setState(() => error = 'New passwords do not match');
                          try {
                            await wallet.changePassword(old.text, next.text);
                            setState(() => ok = 'Password changed');
                          } catch (e) {
                            setState(() => error = errorText(e));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    for (final c in [old, next, confirm]) {
      c.dispose();
    }
  }

  Future<void> _rescan(BuildContext context) async {
    final wallet = context.read<WalletService>();
    await showBModal<void>(
      context,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Rescan'),
            const Muted(
              'Rescan spent outputs to fix a wrong balance quickly. A full rescan re-reads the whole chain from the wallet\'s restore height (slow; history is rebuilt).',
            ),
            const SizedBox(height: 16),
            GhostButton(
              'Rescan spent outputs',
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await wallet.rescanSpent();
                  if (context.mounted) showSnack(context, 'Spent outputs rescanned');
                } catch (e) {
                  if (context.mounted) showSnack(context, errorText(e), error: true);
                }
              },
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              'Full rescan',
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(
                  wallet.rescanBlockchain().catchError((Object e) {
                    if (context.mounted) showSnack(context, errorText(e), error: true);
                  }),
                );
              },
            ),
            const SizedBox(height: 8),
            GhostButton('Cancel', onPressed: () => Navigator.pop(ctx)),
          ],
        );
      },
    );
  }

  Future<void> _keyImages(BuildContext context) async {
    final wallet = context.read<WalletService>();
    final password = TextEditingController();
    String? error;
    await showBModal<void>(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> run(bool export) async {
              setState(() => error = null);
              final path = export ? await getDirectoryPath(confirmButtonText: 'Export here') : (await openFile())?.path;
              if (path == null) return;
              try {
                if (export) {
                  final file = await wallet.exportKeyImages(password.text, path);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showSnack(context, 'Key images exported to $file');
                } else {
                  await wallet.importKeyImages(password.text, path);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showSnack(context, 'Key images imported');
                }
              } catch (e) {
                setState(() => error = errorText(e));
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const H2('Key images'),
                const Muted(
                  'Export key images from a full wallet and import them into its view-only copy to see the correct balance.',
                ),
                const SizedBox(height: 12),
                Field(controller: password, hint: 'Wallet password', obscure: true, autofocus: true),
                ErrorText(error),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: GhostButton('Import', onPressed: () => run(false))),
                    const SizedBox(width: 8),
                    Expanded(child: PrimaryButton('Export', onPressed: () => run(true))),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    password.dispose();
  }

  Future<void> _delete(BuildContext context) async {
    final wallet = context.read<WalletService>();
    final password = TextEditingController();
    String? error;
    await showBModal<void>(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const H2('Delete wallet'),
                Warn(
                  'This removes "${wallet.name}" from this computer. Without your recovery seed the funds are lost forever.',
                  color: BeldexColors.red,
                ),
                const SizedBox(height: 14),
                Field(controller: password, hint: 'Password to confirm', obscure: true, autofocus: true),
                ErrorText(error),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: GhostButton('Cancel', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GhostButton(
                        'Delete',
                        danger: true,
                        onPressed: () async {
                          try {
                            await wallet.deleteWallet(password.text);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setState(() => error = errorText(e));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    password.dispose();
  }
}

enum _Secret { seed, view, spend }

/// Password -> masked secret with eye toggle, copy, and 30 s auto-hide.
class _RevealSecret extends StatefulWidget {
  const _RevealSecret({required this.kind});
  final _Secret kind;
  @override
  State<_RevealSecret> createState() => _RevealSecretState();
}

class _RevealSecretState extends State<_RevealSecret> {
  static const _revealSeconds = 30;
  final _password = TextEditingController();
  WalletSecrets? _secrets;
  bool _visible = false;
  bool _busy = false;
  String? _error;
  int _left = _revealSeconds;
  Timer? _timer;

  String get _title => switch (widget.kind) {
    _Secret.seed => 'Recovery seed',
    _Secret.view => 'Private view key',
    _Secret.spend => 'Private spend key',
  };

  String get _note => switch (widget.kind) {
    _Secret.seed => 'Anyone with these 25 words can spend your funds. Never share them.',
    _Secret.view => 'Allows viewing incoming transactions. Cannot spend funds.',
    _Secret.spend => 'Anyone with this key can spend your funds. Never share it.',
  };

  @override
  void dispose() {
    _timer?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final secrets = await context.read<WalletService>().privateKeys(_password.text);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_left <= 1) {
          if (mounted) Navigator.pop(context);
        } else if (mounted) {
          setState(() => _left--);
        }
      });
      setState(() => _secrets = secrets);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = switch (widget.kind) {
      _Secret.seed => _secrets?.mnemonic,
      _Secret.view => _secrets?.viewKey,
      _Secret.spend => _secrets?.spendKey,
    };
    if (value == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          H2(_title),
          const Muted('Enter your password to reveal.'),
          const SizedBox(height: 10),
          Field(controller: _password, hint: 'Password', obscure: true, autofocus: true, onSubmitted: (_) => _reveal()),
          ErrorText(_error),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: GhostButton('Back', onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton('Reveal', busy: _busy, onPressed: _reveal),
              ),
            ],
          ),
        ],
      );
    }
    final masked = widget.kind == _Secret.seed
        ? value.split(RegExp(r'\s+')).map((w) => '•' * w.length.clamp(3, 8)).join(' ')
        : '${'•' * 15}...${'•' * 15}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        H2(_title),
        Row(
          children: [
            Expanded(child: Muted('Auto-hides in ${_left}s', size: 11)),
            IconButton(
              tooltip: _visible ? 'Hide' : 'Show',
              iconSize: 18,
              onPressed: () => setState(() => _visible = !_visible),
              icon: Icon(
                _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: BeldexColors.green,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BeldexColors.input,
            border: Border.all(color: BeldexColors.green),
          ),
          child: SelectableText(
            _visible ? value : masked,
            style: const TextStyle(color: BeldexColors.green, fontSize: 12, height: 1.7),
          ),
        ),
        const SizedBox(height: 10),
        Warn(_note),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: GhostButton('Close', onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 8),
            Expanded(
              child: PrimaryButton(
                'Copy',
                onPressed: () async {
                  await copyText(value, secret: true);
                  if (context.mounted) showSnack(context, 'Copied — clipboard clears in 60 s');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
