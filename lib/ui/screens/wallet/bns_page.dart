import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/validators.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

const bnsTerms = [
  ('1y', '1 yr', '650 BDX'),
  ('2y', '2 yrs', '1000 BDX'),
  ('5y', '5 yrs', '2000 BDX'),
  ('10y', '10 yrs', '4000 BDX'),
];

class BnsPage extends StatelessWidget {
  const BnsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t('titles.bns.purchase')),
              Tab(text: t('titles.bns.myBns')),
            ],
          ),
          const Expanded(child: TabBarView(children: [_PurchaseTab(), _MyBnsTab()])),
        ],
      ),
    );
  }
}

/// Value fields shared by purchase and update.
class _BnsValues {
  final wallet = TextEditingController();
  final bchat = TextEditingController();
  final belnet = TextEditingController();
  final eth = TextEditingController();

  bool get isEmpty => [wallet, bchat, belnet, eth].every((c) => c.text.trim().isEmpty);

  /// Returns an error message or null.
  Future<String?> validate(WalletService service) async {
    if (wallet.text.trim().isNotEmpty && !await service.validateAddress(wallet.text.trim())) return 'Invalid Address';
    if (bchat.text.trim().isNotEmpty && !isBchatId(bchat.text.trim().toLowerCase())) {
      return t('notification.errors.invalidBchatId');
    }
    final belnetValue = belnet.text.trim().toLowerCase().replaceAll('.bdx', '');
    if (belnetValue.isNotEmpty && !isBelnetAddress(belnetValue)) return 'Invalid Belnet Id';
    if (eth.text.trim().isNotEmpty && !isEthAddress(eth.text.trim())) return 'Invalid Ethereum address';
    return null;
  }

  List<Widget> fields() => [
    TextField(
      controller: wallet,
      decoration: InputDecoration(
        labelText: t('fieldLabels.walletAddress'),
        hintText: t('placeholders.enterWalletAddress'),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: bchat,
      decoration: InputDecoration(labelText: t('fieldLabels.bchatId'), hintText: t('placeholders.enterBchatId')),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: belnet,
      decoration: InputDecoration(labelText: t('fieldLabels.belnetId'), hintText: t('placeholders.enterBelnetId')),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: eth,
      decoration: InputDecoration(labelText: t('fieldLabels.eth'), hintText: t('placeholders.enterEthAddress')),
    ),
  ];

  void clear() {
    for (final c in [wallet, bchat, belnet, eth]) {
      c.clear();
    }
  }

  void dispose() {
    for (final c in [wallet, bchat, belnet, eth]) {
      c.dispose();
    }
  }
}

class _PurchaseTab extends StatefulWidget {
  const _PurchaseTab();
  @override
  State<_PurchaseTab> createState() => _PurchaseTabState();
}

class _PurchaseTabState extends State<_PurchaseTab> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _backup = TextEditingController();
  final _values = _BnsValues();
  String _years = '1y';

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _backup.dispose();
    _values.dispose();
    super.dispose();
  }

  Future<void> _purchase() async {
    final wallet = context.read<WalletService>();
    final rawName = _name.text.trim().toLowerCase().replaceAll(RegExp(r'\.bdx$'), '');
    String? error;
    if (rawName.isEmpty) {
      error = t('notification.errors.enterName');
    } else if (rawName.length > (rawName.contains('-') ? 63 : 32)) {
      error = t('notification.errors.invalidNameLength');
    } else if (rawName.startsWith('-') || rawName.endsWith('-')) {
      error = t('notification.errors.invalidNameHypenNotAllowed');
    } else if (!isBnsName(rawName)) {
      error = t('notification.errors.invalidNameFormat');
    } else if (_values.isEmpty) {
      error = 'Please add at least one value (wallet, BChat, Belnet or ETH)';
    } else if (_owner.text.trim().isNotEmpty && !await wallet.validateAddress(_owner.text.trim())) {
      error = t('notification.errors.invalidOwner');
    } else if (_backup.text.trim().isNotEmpty && !await wallet.validateAddress(_backup.text.trim())) {
      error = t('notification.errors.invalidBackupOwner');
    } else {
      error = await _values.validate(wallet);
    }
    if (!mounted) return;
    if (error != null) return showSnack(context, error, error: true);
    if (wallet.unlockedBalance < 21 * atomicUnitsPerBdx) {
      return showSnack(context, t('notification.errors.notEnoughBalance'), error: true);
    }

    final term = bnsTerms.firstWhere((b) => b.$1 == _years);
    if (!await confirmDialog(
          context,
          title: t('dialog.confirmPurchase.title'),
          message: '${WalletService.fullBnsName(rawName)} · ${term.$2} · ${term.$3}',
          okLabel: t('dialog.confirmPurchase.ok'),
        ) ||
        !mounted) {
      return;
    }
    final password = await confirmWithPassword(
      context,
      title: t('dialog.purchase.title'),
      okLabel: t('dialog.purchase.ok'),
      noPasswordMessage: t('dialog.purchase.message'),
    );
    if (password == null || !mounted) return;
    final ok = await runWithProgress(context, () async {
      await wallet.purchaseBns(
        password: password,
        years: _years,
        name: rawName,
        owner: _owner.text,
        backupOwner: _backup.text,
        valueWallet: _values.wallet.text.trim(),
        valueBchat: _values.bchat.text.trim().toLowerCase(),
        valueBelnet: _values.belnet.text.trim().toLowerCase(),
        valueEth: _values.eth.text.trim(),
      );
      return true;
    }, message: 'Sending transaction');
    if (ok == true && mounted) {
      showSnack(context, t('notification.positive.namePurchased'));
      _name.clear();
      _owner.clear();
      _backup.clear();
      _values.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      SectionCard(
        title: t('strings.bns.bnsRegistration'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('strings.bnsPurchaseDescription'), style: const TextStyle(color: BeldexColors.muted)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: t('fieldLabels.name'),
                      hintText: t('placeholders.bnsName'),
                      suffixText: '.bdx',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _years,
                    decoration: InputDecoration(labelText: t('fieldLabels.year')),
                    items: [for (final b in bnsTerms) DropdownMenuItem(value: b.$1, child: Text('${b.$2} · ${b.$3}'))],
                    onChanged: (v) => setState(() => _years = v ?? '1y'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _owner,
              decoration: InputDecoration(
                labelText: '${t('fieldLabels.owner')} (${t('fieldLabels.optional')})',
                hintText: t('placeholders.bnsOwner'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backup,
              decoration: InputDecoration(
                labelText: '${t('fieldLabels.backupOwner')} (${t('fieldLabels.optional')})',
                hintText: t('placeholders.bnsBackupOwner'),
              ),
            ),
            const SizedBox(height: 20),
            ..._values.fields(),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _purchase, child: Text(t('buttons.purchase'))),
            ),
          ],
        ),
      ),
    ],
  );
}

class _MyBnsTab extends StatefulWidget {
  const _MyBnsTab();
  @override
  State<_MyBnsTab> createState() => _MyBnsTabState();
}

class _MyBnsTabState extends State<_MyBnsTab> {
  final _decryptName = TextEditingController();
  bool _decrypting = false;

  @override
  void dispose() {
    _decryptName.dispose();
    super.dispose();
  }

  Future<void> _decrypt() async {
    final name = _decryptName.text.trim();
    if (name.isEmpty) return showSnack(context, t('notification.errors.enterName'), error: true);
    if (!isBchatOrBelnetName(name)) return showSnack(context, t('notification.errors.invalidNameFormat'), error: true);
    setState(() => _decrypting = true);
    final full = WalletService.fullBnsName(name);
    final ok = await context.read<WalletService>().decryptBnsRecord(name);
    if (!mounted) return;
    setState(() => _decrypting = false);
    if (ok) {
      _decryptName.clear();
      showSnack(context, t('notification.positive.decryptedBNSRecord', {'name': full}));
    } else {
      showSnack(context, t('notification.errors.decryptBNSRecord', {'name': full}), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletService>();
    final records = wallet.bnsRecords;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (records.any((r) => r.isLocked))
          SectionCard(
            title: t('fieldLabels.decryptRecord'),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _decryptName,
                    decoration: InputDecoration(hintText: t('placeholders.bnsDecryptName')),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _decrypting ? null : _decrypt, child: Text(t('buttons.decrypt'))),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SectionCard(
          title: t('titles.bns.myBns'),
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: wallet.refreshBnsRecords),
          child: records.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('No BNS records owned by this wallet yet.'))
              : Column(children: [for (final r in records) _RecordTile(record: r)]),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});
  final BnsRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        r.isLocked ? Icons.lock_outline : Icons.lock_open,
        color: r.isLocked ? BeldexColors.muted : BeldexColors.green,
      ),
      title: Text(r.isLocked ? shorten(r.nameHash) : r.name!, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${t('strings.blockHeight')}: ${r.updateHeight}'
        '${r.expirationHeight != null ? ' · ${t('strings.expirationHeight')}: ${r.expirationHeight}' : ''}',
      ),
      children: [
        DetailRow(t('fieldLabels.owner'), r.owner, copyable: true, mono: true),
        if (r.backupOwner.isNotEmpty)
          DetailRow(t('fieldLabels.backupOwner'), r.backupOwner, copyable: true, mono: true),
        if (!r.isLocked) ...[
          if (r.valueWallet.isNotEmpty)
            DetailRow(t('fieldLabels.walletAddress'), r.valueWallet, copyable: true, mono: true),
          if (r.valueBchat.isNotEmpty) DetailRow(t('fieldLabels.bchatId'), r.valueBchat, copyable: true, mono: true),
          if (r.valueBelnet.isNotEmpty) DetailRow(t('fieldLabels.belnetId'), r.valueBelnet, copyable: true, mono: true),
          if (r.valueEth.isNotEmpty) DetailRow(t('fieldLabels.eth'), r.valueEth, copyable: true, mono: true),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(onPressed: () => _renew(context, r), child: Text(t('buttons.bnsRenew'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _update(context, r), child: Text(t('buttons.bnsUpdate'))),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _renew(BuildContext context, BnsRecord r) async {
    var years = '1y';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('dialog.confirmRenew.title')),
          content: SizedBox(
            width: 380,
            child: RadioGroup<String>(
              groupValue: years,
              onChanged: (v) => setState(() => years = v ?? '1y'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.name!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final b in bnsTerms) RadioListTile<String>(value: b.$1, title: Text('${b.$2} · ${b.$3}')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('dialog.confirmRenew.ok'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final password = await confirmWithPassword(
      context,
      title: t('dialog.renew.title'),
      okLabel: t('dialog.renew.ok'),
      noPasswordMessage: t('dialog.renew.message'),
    );
    if (password == null || !context.mounted) return;
    final done = await runWithProgress(context, () async {
      await context.read<WalletService>().renewBns(password, r.name!, years);
      return true;
    });
    if (done == true && context.mounted) showSnack(context, t('notification.positive.nameRenewed'));
  }

  Future<void> _update(BuildContext context, BnsRecord r) async {
    final wallet = context.read<WalletService>();
    final values = _BnsValues();
    final owner = TextEditingController();
    final backup = TextEditingController(text: r.backupOwner);
    var ownerMode = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${t('buttons.bnsUpdate')} · ${r.name}'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(t('fieldLabels.updateValues'))),
                      ButtonSegment(value: true, label: Text(t('fieldLabels.updateOwner'))),
                    ],
                    selected: {ownerMode},
                    onSelectionChanged: (s) => setState(() => ownerMode = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (ownerMode) ...[
                    TextField(
                      controller: owner,
                      decoration: InputDecoration(labelText: t('fieldLabels.OwnerWalletaddress')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: backup,
                      decoration: InputDecoration(labelText: t('fieldLabels.backupOwnerWalletAddress')),
                    ),
                  ] else
                    ...values.fields(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
            FilledButton(
              onPressed: () async {
                String? error;
                if (ownerMode) {
                  if (!await wallet.validateAddress(owner.text.trim())) error = t('notification.errors.invalidOwner');
                  if (owner.text.trim() == r.owner) error = 'same owner address';
                } else {
                  error = values.isEmpty ? 'Please change at least one value' : await values.validate(wallet);
                }
                if (!ctx.mounted) return;
                if (error != null) return showSnack(ctx, error, error: true);
                Navigator.pop(ctx, true);
              },
              child: Text(t('dialog.confirmUpdate.ok')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final password = await confirmWithPassword(
        context,
        title: t('dialog.bnsUpdate.title'),
        okLabel: t('dialog.bnsUpdate.ok'),
        noPasswordMessage: t('dialog.bnsUpdate.message'),
      );
      if (password != null && context.mounted) {
        final done = await runWithProgress(context, () async {
          await wallet.updateBns(
            password: password,
            name: r.name!,
            owner: ownerMode ? owner.text.trim() : null,
            backupOwner: ownerMode ? backup.text.trim() : null,
            valueWallet: ownerMode ? null : values.wallet.text.trim(),
            valueBchat: ownerMode ? null : values.bchat.text.trim().toLowerCase(),
            valueBelnet: ownerMode ? null : values.belnet.text.trim().toLowerCase(),
            valueEth: ownerMode ? null : values.eth.text.trim(),
          );
          return true;
        }, message: 'Sending transaction');
        if (done == true && context.mounted) showSnack(context, t('notification.positive.bnsRecordUpdated'));
      }
    }
    values.dispose();
    owner.dispose();
    backup.dispose();
  }
}
