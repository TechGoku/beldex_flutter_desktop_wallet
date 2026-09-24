import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../services/wallet_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class AdvancedPage extends StatelessWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t('titles.advanced.prove')),
              Tab(text: t('titles.advanced.checkTransaction')),
              Tab(text: t('titles.advanced.signAndVerify')),
            ],
          ),
          const Expanded(child: TabBarView(children: [_ProveTab(), _CheckTab(), _SignVerifyTab()])),
        ],
      ),
    );
  }
}

class _ProveTab extends StatefulWidget {
  const _ProveTab();
  @override
  State<_ProveTab> createState() => _ProveTabState();
}

class _ProveTabState extends State<_ProveTab> {
  final _txid = TextEditingController(), _address = TextEditingController(), _message = TextEditingController();
  String? _signature;

  @override
  void dispose() {
    for (final c in [_txid, _address, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final wallet = context.read<WalletService>();
    if (_txid.text.trim().isEmpty) return showSnack(context, t('notification.errors.enterTransactionId'), error: true);
    if (_address.text.trim().isNotEmpty && !await wallet.validateAddress(_address.text.trim())) {
      if (mounted) showSnack(context, t('notification.errors.invalidAddress'), error: true);
      return;
    }
    if (!mounted) return;
    final r = await runWithProgress(context, () => wallet.proveTransaction(_txid.text, _address.text, _message.text));
    if (r != null && mounted) setState(() => _signature = r['signature'] as String?);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('strings.proveTransactionDescription'), style: const TextStyle(color: BeldexColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _txid,
              decoration: InputDecoration(
                labelText: t('fieldLabels.transactionId'),
                hintText: t('placeholders.pasteTransactionId'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: '${t('fieldLabels.address')} (${t('fieldLabels.optional')})',
                hintText: t('placeholders.recipientWalletAddress'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              decoration: InputDecoration(
                labelText: '${t('fieldLabels.message')} (${t('fieldLabels.optional')})',
                hintText: t('placeholders.proveOptionalMessage'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    for (final c in [_txid, _address, _message]) {
                      c.clear();
                    }
                    setState(() => _signature = null);
                  },
                  child: Text(t('buttons.clear')),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _generate, child: Text(t('buttons.generate'))),
              ],
            ),
            if (_signature != null) ...[
              const Divider(height: 32),
              DetailRow(t('fieldLabels.signature'), _signature!, copyable: true, mono: true),
            ],
          ],
        ),
      ),
    ],
  );
}

class _CheckTab extends StatefulWidget {
  const _CheckTab();
  @override
  State<_CheckTab> createState() => _CheckTabState();
}

class _CheckTabState extends State<_CheckTab> {
  final _txid = TextEditingController(),
      _address = TextEditingController(),
      _message = TextEditingController(),
      _signature = TextEditingController();
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    for (final c in [_txid, _address, _message, _signature]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _check() async {
    final wallet = context.read<WalletService>();
    if (_txid.text.trim().isEmpty) return showSnack(context, t('notification.errors.enterTransactionId'), error: true);
    if (_signature.text.trim().isEmpty)
      return showSnack(context, t('notification.errors.enterTransactionProof'), error: true);
    if (_address.text.trim().isNotEmpty && !await wallet.validateAddress(_address.text.trim())) {
      if (mounted) showSnack(context, t('notification.errors.invalidAddress'), error: true);
      return;
    }
    if (!mounted) return;
    final r = await runWithProgress(
      context,
      () => wallet.checkTransaction(_txid.text, _signature.text, _address.text, _message.text),
    );
    if (r != null && mounted) setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('strings.checkTransaction.description'), style: const TextStyle(color: BeldexColors.muted)),
              const SizedBox(height: 16),
              TextField(
                controller: _txid,
                decoration: InputDecoration(
                  labelText: t('fieldLabels.transactionId'),
                  hintText: t('placeholders.pasteTransactionId'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: InputDecoration(labelText: '${t('fieldLabels.address')} (${t('fieldLabels.optional')})'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                decoration: InputDecoration(labelText: '${t('fieldLabels.message')} (${t('fieldLabels.optional')})'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _signature,
                decoration: InputDecoration(
                  labelText: t('fieldLabels.signature'),
                  hintText: t('placeholders.pasteTransactionProof'),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _check, child: Text(t('buttons.check'))),
              ),
              if (r != null) ...[
                const Divider(height: 32),
                DetailRow(
                  t('strings.checkTransaction.validTransaction.yes').split(' ').first,
                  r['good'] == true
                      ? t('strings.checkTransaction.validTransaction.yes')
                      : t('strings.checkTransaction.validTransaction.no'),
                ),
                if (r['received'] != null)
                  DetailRow(
                    t('strings.checkTransaction.infoTitles.received'),
                    '${formatBdx((r['received'] as num).toInt())} BDX',
                  ),
                if (r['in_pool'] != null) DetailRow(t('strings.checkTransaction.infoTitles.inPool'), '${r['in_pool']}'),
                if (r['confirmations'] != null)
                  DetailRow(t('strings.checkTransaction.infoTitles.confirmations'), '${r['confirmations']}'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SignVerifyTab extends StatefulWidget {
  const _SignVerifyTab();
  @override
  State<_SignVerifyTab> createState() => _SignVerifyTabState();
}

class _SignVerifyTabState extends State<_SignVerifyTab> {
  final _toSign = TextEditingController();
  final _data = TextEditingController(), _address = TextEditingController(), _signature = TextEditingController();
  String? _signed;

  @override
  void dispose() {
    for (final c in [_toSign, _data, _address, _signature]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.read<WalletService>();
    final viewOnly = context.select<WalletService, bool>((w) => w.viewOnly);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: t('titles.advanced.sign'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('strings.signAndVerifyDescription'), style: const TextStyle(color: BeldexColors.muted)),
              const SizedBox(height: 16),
              if (viewOnly)
                Text(t('strings.cannotSign'))
              else ...[
                TextField(
                  controller: _toSign,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: t('fieldLabels.data'), hintText: t('placeholders.dataToSign')),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      final sig = await runWithProgress(context, () => wallet.sign(_toSign.text));
                      if (sig != null && mounted) setState(() => _signed = sig);
                    },
                    child: Text(t('buttons.sign')),
                  ),
                ),
                if (_signed != null) ...[
                  DetailRow(t('fieldLabels.signature'), _signed!, copyable: true, mono: true),
                  DetailRow(t('fieldLabels.address'), wallet.address, copyable: true, mono: true),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: t('titles.advanced.verify'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _data,
                maxLines: 3,
                decoration: InputDecoration(labelText: t('fieldLabels.data'), hintText: t('placeholders.unsignedData')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: InputDecoration(
                  labelText: t('fieldLabels.address'),
                  hintText: t('placeholders.addressOfSigner'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _signature,
                decoration: InputDecoration(
                  labelText: t('fieldLabels.signature'),
                  hintText: t('placeholders.signature'),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (!await wallet.validateAddress(_address.text.trim())) {
                      if (context.mounted) showSnack(context, t('notification.errors.invalidAddress'), error: true);
                      return;
                    }
                    if (!context.mounted) return;
                    final good = await runWithProgress(
                      context,
                      () => wallet.verify(_data.text, _address.text.trim(), _signature.text.trim()),
                    );
                    if (good == null || !context.mounted) return;
                    showSnack(
                      context,
                      good ? t('notification.positive.signatureVerified') : t('notification.errors.invalidSignature'),
                      error: !good,
                    );
                  },
                  child: Text(t('buttons.verify')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
