import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/daemon_service.dart';
import '../../services/models.dart';
import '../../services/swap/swap_models.dart';
import '../../services/wallet_service.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

/// Translates an exception into a user-facing message.
String errorText(Object error) {
  if (error is WalletException) {
    return error.i18nKey != null ? t(error.i18nKey!, error.args) : error.message ?? '';
  }
  if (error is SwapException) return error.message;
  if (error is StateError) return error.message;
  return '$error';
}

void showSnack(BuildContext context, String message, {bool error = false, bool warning = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: warning ? Colors.black : Colors.white)),
        backgroundColor: error ? BeldexColors.negative : (warning ? BeldexColors.warning : BeldexColors.green),
        duration: Duration(milliseconds: error ? 3500 : 2000),
      ),
    );
}

void showError(BuildContext context, Object error) => showSnack(context, errorText(error), error: true);

Future<void> copyToClipboard(BuildContext context, String value, {String? message}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showSnack(context, message ?? t('notification.positive.copied', {'item': ''}).trim());
}

/// Runs [action] with a blocking progress overlay, reporting errors.
Future<T?> runWithProgress<T>(BuildContext context, Future<T> Function() action, {String? message}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[const SizedBox(height: 16), Text(message)],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    return await action();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  } finally {
    navigator.pop();
  }
}

/// Asks for the wallet password (or a plain confirmation when the wallet
/// has no password). Returns the password ('' when none), or null when
/// the user cancels. Mirrors the Electron wallet's password mixin.
Future<String?> confirmWithPassword(
  BuildContext context, {
  required String title,
  required String okLabel,
  String? noPasswordMessage,
  bool destructive = false,
}) async {
  final wallet = context.read<WalletService>();
  final hasPassword = await wallet.hasPassword();
  if (!context.mounted) return null;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: hasPassword
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('dialog.password.message')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                ],
              )
            : Text(noPasswordMessage ?? ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: BeldexColors.negative) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  final password = controller.text;
  controller.dispose();
  return ok == true ? password : null;
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String okLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 440, child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: BeldexColors.negative) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shows the fee/amount of a prepared transfer; true = send it.
Future<bool> confirmTransfer(BuildContext context, PendingTransfer pending) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('dialog.confirmTransaction.title')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(t('dialog.confirmTransaction.sendTo'), pending.destination, mono: true),
            _kv(t('strings.transactions.amount'), '${formatBdx(pending.totalAmount)} BDX'),
            _kv(t('strings.transactions.fee'), '${formatBdx(pending.totalFee)} BDX'),
            _kv(
              t('dialog.confirmTransaction.priority'),
              pending.isFlash ? t('strings.priorityOptions.flash') : t('strings.priorityOptions.slow'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('dialog.confirmTransaction.confirm'))),
      ],
    ),
  );
  return ok == true;
}

Widget _kv(String k, String v, {bool mono = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: const TextStyle(color: BeldexColors.muted, fontSize: 12)),
      const SizedBox(height: 2),
      SelectableText(v, style: TextStyle(fontFamily: mono ? 'monospace' : null)),
    ],
  ),
);

/// Label/value row used in detail views.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.copyable = false, this.mono = false});
  final String label;
  final String value;
  final bool copyable;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: const TextStyle(color: BeldexColors.muted)),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: TextStyle(fontFamily: mono ? 'monospace' : null, fontSize: 13),
            ),
          ),
          if (copyable && value.isNotEmpty)
            IconButton(
              tooltip: t('menuItems.copyAddress'),
              iconSize: 18,
              icon: const Icon(Icons.copy),
              onPressed: () => copyToClipboard(context, value),
            ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(20),
    this.trailing,
  });
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BeldexColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BeldexColors.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: const TextStyle(fontFamily: 'Michroma', fontSize: 12, letterSpacing: 1),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.hint});
  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: BeldexColors.muted),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                style: const TextStyle(color: BeldexColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showQrDialog(BuildContext context, String data, {String? title}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: title != null ? Text(title) : null,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: data, size: 280, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            SelectableText(data, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => copyToClipboard(ctx, data), child: Text(t('menuItems.copyAddress'))),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('dialog.buttons.ok'))),
      ],
    ),
  );
}

/// Bottom status bar: daemon/wallet heights and sync state.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final daemonInfo = context.select<DaemonService, int>((d) => d.info.height);
    final targetHeight = context.select<DaemonService, int>((d) => d.info.targetHeight);
    final walletHeight = context.select<WalletService, int>((w) => w.height);
    final syncing = context.select<WalletService, bool>((w) => w.isSyncing);
    final isOpen = context.select<WalletService, bool>((w) => w.isOpen);
    final local = app.config.daemon.runsLocally;

    final target = local ? (targetHeight > daemonInfo ? targetHeight : daemonInfo) : daemonInfo;
    final daemonSyncing = local && daemonInfo < target;
    final pct = target == 0 ? 0.0 : (walletHeight / target * 100).clamp(0, 100).toDouble();

    String status;
    Color color;
    if (daemonSyncing) {
      status = t('footer.syncing');
      color = BeldexColors.warning;
    } else if (isOpen && (syncing || walletHeight < target - 1)) {
      status = t('footer.scanning');
      color = BeldexColors.warning;
    } else {
      status = t('footer.ready');
      color = BeldexColors.greenBright;
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF15151D) : Colors.black12,
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            status.toUpperCase(),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 20),
          Text(
            '${t('footer.remote')}: ${app.config.daemon.type == DaemonType.remote ? app.config.daemon.remoteHost : 'local'}',
            style: const TextStyle(fontSize: 12, color: BeldexColors.muted),
          ),
          const Spacer(),
          Text('${t('footer.daemon')}: $daemonInfo', style: const TextStyle(fontSize: 12, color: BeldexColors.muted)),
          if (isOpen) ...[
            const SizedBox(width: 20),
            Text(
              '${t('footer.wallet')}: $walletHeight / $target (${pct.toStringAsFixed(1)}%)',
              style: const TextStyle(fontSize: 12, color: BeldexColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class BdxAmount extends StatelessWidget {
  const BdxAmount(this.atomic, {super.key, this.style, this.prefix = '', this.round = false});
  final int atomic;
  final TextStyle? style;
  final String prefix;
  final bool round;

  @override
  Widget build(BuildContext context) => Text('$prefix${formatBdx(atomic, round: round)} BDX', style: style);
}

/// Password field pair used by create/restore/import forms.
class PasswordFields extends StatelessWidget {
  const PasswordFields({super.key, required this.password, required this.confirm});
  final TextEditingController password;
  final TextEditingController confirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(labelText: t('fieldLabels.password')),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: confirm,
            obscureText: true,
            decoration: InputDecoration(labelText: t('fieldLabels.confirmPassword')),
          ),
        ),
      ],
    );
  }
}

String netLabel(NetType n) => switch (n) {
  NetType.mainnet => 'Main Net',
  NetType.stagenet => 'Stage Net',
  NetType.testnet => 'Test Net',
};
