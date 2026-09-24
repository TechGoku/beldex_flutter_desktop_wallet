import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/validators.dart';
import '../../../services/daemon_service.dart';
import '../../../services/wallet_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../explorer.dart';

typedef Node = Map<String, dynamic>;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
List<Map<String, dynamic>> _contributors(Node n) =>
    ((n['contributors'] as List?) ?? const []).cast<Map<String, dynamic>>();

/// Remaining stake that can still be contributed (atomic units).
int openForContribution(Node n) {
  final requirement = _int(n['staking_requirement']);
  final reserved = _int(n['total_reserved']);
  return requirement > reserved ? requirement - reserved : 0;
}

/// Minimum contribution, computed the same way as explorer.beldex.io.
int minContribution(Node n) {
  const maxContributors = 4;
  final count = _contributors(n).length;
  if (n['funded'] == true || count >= maxContributors) return 0;
  return openForContribution(n) ~/ (maxContributors - count);
}

double feePercent(Node n) => operatorFeePercent(_int(n['portions_for_operator']));

class MasterNodesPage extends StatelessWidget {
  const MasterNodesPage({super.key, this.initialTab = 0});

  /// 0 staking, 1 registration, 2 my stakes.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t('titles.masterNode.staking')),
              Tab(text: t('titles.masterNode.registration')),
              Tab(text: t('titles.masterNode.myStakes')),
            ],
          ),
          const Expanded(child: TabBarView(children: [_StakingTab(), _RegistrationTab(), _MyStakesTab()])),
        ],
      ),
    );
  }
}

class _StakingTab extends StatefulWidget {
  const _StakingTab();
  @override
  State<_StakingTab> createState() => _StakingTabState();
}

class _StakingTabState extends State<_StakingTab> {
  final _key = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _amount.dispose();
    super.dispose();
  }

  List<Node> _awaiting(List<Node> nodes, String ourAddress) {
    bool ours(Node n) => _contributors(n).any((c) => c['address'] == ourAddress && _int(c['amount']) > 0);
    final awaiting = nodes
        .where((n) => n['active'] != true && n['funded'] != true && _int(n['requested_unlock_height']) == 0)
        .toList();
    int byFee(Node a, Node b) => feePercent(a).compareTo(feePercent(b));
    final reserved = awaiting.where(ours).toList()..sort(byFee);
    final open = awaiting.where((n) => !ours(n)).toList()..sort(byFee);
    return [...reserved, ...open];
  }

  Future<void> _stake() async {
    final wallet = context.read<WalletService>();
    final amount = parseBdx(_amount.text);
    final key = _key.text.trim();
    String? error;
    if (!isMasterNodeKey(key)) {
      error = t('notification.errors.invalidMasterNodeKey');
    } else if (amount == null) {
      error = t('notification.errors.invalidAmount');
    } else if (amount <= 0) {
      error = t('notification.errors.zeroAmount');
    } else if (amount > wallet.unlockedBalance) {
      error = t('notification.errors.notEnoughBalance');
    }
    if (error != null) return showSnack(context, error, error: true);
    final password = await confirmWithPassword(
      context,
      title: t('dialog.stake.title'),
      okLabel: t('dialog.stake.ok'),
      noPasswordMessage: t('dialog.stake.message'),
    );
    if (password == null || !mounted) return;
    final ok = await runWithProgress(context, () async {
      await wallet.stake(password, amount!, key);
      return true;
    }, message: 'Staking...');
    if (ok == true && mounted) {
      showSnack(context, t('notification.positive.stakeSuccess'));
      _key.clear();
      _amount.clear();
    }
  }

  Future<void> _sweepAll() async {
    final wallet = context.read<WalletService>();
    if (!await confirmDialog(
          context,
          title: t('dialog.sweepAllWarning.title'),
          message: t('dialog.sweepAllWarning.message'),
          okLabel: t('dialog.sweepAllWarning.ok'),
        ) ||
        !mounted) {
      return;
    }
    final password = await confirmWithPassword(
      context,
      title: t('dialog.sweepAll.title'),
      okLabel: t('dialog.sweepAll.ok'),
      noPasswordMessage: t('dialog.sweepAll.message'),
    );
    if (password == null || !mounted) return;
    final pending = await runWithProgress(
      context,
      () => wallet.prepareTransfer(
        password: password,
        amount: wallet.unlockedBalance,
        address: wallet.address,
        priority: 0,
        sweepAll: true,
      ),
    );
    if (pending == null || !mounted || !await confirmTransfer(context, pending) || !mounted) return;
    final ok = await runWithProgress(context, () async {
      await wallet.relay(pending);
      return true;
    });
    if (ok == true && mounted) showSnack(context, t('notification.positive.sendSuccess'));
  }

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonService>();
    final address = context.select<WalletService, String>((w) => w.address);
    final nodes = _awaiting(daemon.masterNodes, address);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: t('titles.masterNode.staking'),
          trailing: TextButton.icon(
            onPressed: _sweepAll,
            icon: const Icon(Icons.cleaning_services),
            label: Text(t('buttons.sweepAll')),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('strings.masterNodeStartStakingDescription'), style: const TextStyle(color: BeldexColors.muted)),
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: t('fieldLabels.masterNodeKey'),
                  hintText: t('placeholders.hexCharacters'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,9}'))],
                decoration: InputDecoration(labelText: t('fieldLabels.amount'), suffixText: 'BDX'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _stake, child: Text(t('buttons.stake'))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: t('titles.availableForContribution'),
          trailing: IconButton(
            icon: daemon.masterNodesFetching
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: daemon.refreshMasterNodes,
          ),
          child: nodes.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(t('strings.noMasterNodesCurrentlyAvailable')))
              : Column(
                  children: [
                    for (final n in nodes)
                      _NodeTile(
                        node: n,
                        subtitle:
                            '${feePercent(n).toStringAsFixed(2)}% ${t('strings.transactions.fee')} · ${t('strings.masterNodeDetails.minContribution')}: ${formatBdx(minContribution(n), round: true)} BDX · ${t('strings.masterNodeDetails.maxContribution')}: ${formatBdx(openForContribution(n), round: true)} BDX',
                        action: TextButton(
                          onPressed: () {
                            _key.text = '${n['master_node_pubkey']}';
                            _amount.text = (minContribution(n) / atomicUnitsPerBdx).toStringAsFixed(4);
                            showSnack(context, t('notification.positive.masterNodeInfoFilled'));
                          },
                          child: Text(t('buttons.stake')),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.node, required this.subtitle, this.action});
  final Node node;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final key = '${node['master_node_pubkey']}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(shorten(key, head: 20, tail: 20), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: action,
      onTap: () => showNodeDetails(context, node),
    );
  }
}

Future<void> showNodeDetails(BuildContext context, Node n) {
  final wallet = context.read<WalletService>();
  final book = {for (final e in wallet.addressBook) e.address: e.name};
  final key = '${n['master_node_pubkey']}';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('titles.masterNodeDetails')),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DetailRow(t('strings.masterNodeDetails.masterNodeKey'), key, copyable: true, mono: true),
              DetailRow(t('strings.masterNodeDetails.operatorFee'), '${feePercent(n).toStringAsFixed(2)}%'),
              DetailRow(
                t('strings.masterNodeDetails.stakingRequirement'),
                '${formatBdx(_int(n['staking_requirement']))} BDX',
              ),
              DetailRow(
                t('strings.masterNodeDetails.totalContributed'),
                '${formatBdx(_int(n['total_contributed']))} BDX',
              ),
              DetailRow(t('strings.masterNodeDetails.registrationHeight'), '${n['registration_height'] ?? '-'}'),
              DetailRow(
                t('strings.masterNodeDetails.lastRewardBlockHeight'),
                '${n['last_reward_block_height'] ?? '-'}',
              ),
              if (_int(n['last_uptime_proof']) > 0)
                DetailRow(
                  t('strings.masterNodeDetails.lastUptimeProof'),
                  formatTimestamp(_int(n['last_uptime_proof'])),
                ),
              if (_int(n['requested_unlock_height']) > 0)
                DetailRow(t('strings.masterNodeDetails.unlockHeight'), '${n['requested_unlock_height']}'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('strings.masterNodeDetails.contributors'), style: Theme.of(ctx).textTheme.titleSmall),
              ),
              for (final c in _contributors(n))
                DetailRow(
                  [
                    if (c['address'] == n['operator_address']) t('strings.operator'),
                    if (c['address'] == wallet.address) t('strings.me'),
                    if (book[c['address']] != null) book[c['address']]!,
                  ].join(' · ').ifEmpty(t('strings.contributor')),
                  '${c['address']}\n${formatBdx(_int(c['amount']))} BDX',
                  mono: true,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(explorerUrl(wallet.netType, 'master_node', key)),
          child: Text(t('buttons.viewOnExplorer')),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('buttons.close'))),
      ],
    ),
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _RegistrationTab extends StatefulWidget {
  const _RegistrationTab();
  @override
  State<_RegistrationTab> createState() => _RegistrationTabState();
}

class _RegistrationTabState extends State<_RegistrationTab> {
  final _command = TextEditingController();

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final command = _command.text.trim();
    if (command.isEmpty) return showSnack(context, t('notification.errors.invalidMasterNodeCommand'), error: true);
    final wallet = context.read<WalletService>();
    final password = await confirmWithPassword(
      context,
      title: t('dialog.registerMasterNode.title'),
      okLabel: t('dialog.registerMasterNode.ok'),
      noPasswordMessage: t('dialog.registerMasterNode.message'),
    );
    if (password == null || !mounted) return;
    final ok = await runWithProgress(context, () async {
      await wallet.registerMasterNode(password, command);
      return true;
    }, message: 'Registering...');
    if (ok == true && mounted) {
      showSnack(context, t('notification.positive.registerMasterNodeSuccess'));
      _command.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      SectionCard(
        title: t('titles.masterNode.registration'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('strings.masterNodeRegistrationDescription'), style: const TextStyle(color: BeldexColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _command,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(labelText: t('fieldLabels.masterNodeCommand')),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _register, child: Text(t('buttons.registerMasterNode'))),
            ),
          ],
        ),
      ),
    ],
  );
}

class _MyStakesTab extends StatefulWidget {
  const _MyStakesTab();
  @override
  State<_MyStakesTab> createState() => _MyStakesTabState();
}

class _MyStakesTabState extends State<_MyStakesTab> {
  List<Map<String, dynamic>>? _deregistered;

  Future<void> _unlock(Node n) async {
    final wallet = context.read<WalletService>();
    final key = '${n['master_node_pubkey']}';
    if (!await confirmDialog(
          context,
          title: t('dialog.unlockMasterNodeWarning.title'),
          message: t('dialog.unlockMasterNodeWarning.message'),
          okLabel: t('dialog.unlockMasterNodeWarning.ok'),
        ) ||
        !mounted) {
      return;
    }
    final password = await confirmWithPassword(
      context,
      title: t('dialog.unlockMasterNode.title'),
      okLabel: t('dialog.unlockMasterNode.ok'),
      noPasswordMessage: t('dialog.unlockMasterNode.message'),
    );
    if (password == null || !mounted) return;
    final check = await runWithProgress(context, () => wallet.canRequestUnlock(password, key));
    if (check == null || !mounted) return;
    if (!check.$1)
      return showSnack(
        context,
        check.$2.isEmpty ? t('notification.errors.failedMasterNodeUnlock') : check.$2,
        error: true,
      );
    if (!await confirmDialog(
          context,
          title: t('dialog.unlockMasterNode.confirmTitle'),
          message: check.$2,
          okLabel: t('dialog.unlockMasterNode.ok'),
        ) ||
        !mounted) {
      return;
    }
    final result = await runWithProgress(context, () => wallet.requestUnlock(key), message: 'Unlocking...');
    if (result != null && mounted) showSnack(context, result.$2, error: !result.$1);
  }

  Future<void> _checkDeregistered() async {
    final wallet = context.read<WalletService>();
    final password = await confirmWithPassword(
      context,
      title: t('dialog.showMasterNode.title'),
      okLabel: t('dialog.showMasterNode.masterNode'),
      noPasswordMessage: t('dialog.showMasterNode.message'),
    );
    if (password == null || !mounted) return;
    final list = await runWithProgress(context, () => wallet.deregisteredStakes(password));
    if (list != null && mounted) setState(() => _deregistered = list);
  }

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonService>();
    final address = context.select<WalletService, String>((w) => w.address);
    final mine = [
      for (final n in daemon.masterNodes)
        if (_contributors(n).any((c) => c['address'] == address && _int(c['amount']) > 0)) n,
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: t('titles.currentlyStakedNodes'),
          child: mine.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(t('strings.noMasterNodesCurrentlyAvailable')))
              : Column(
                  children: [
                    for (final n in mine)
                      _NodeTile(
                        node: n,
                        subtitle: [
                          n['operator_address'] == address ? t('strings.operator') : t('strings.contributor'),
                          '${formatBdx(_int(_contributors(n).firstWhere((c) => c['address'] == address)['amount']))} BDX',
                          if (_int(n['requested_unlock_height']) > 0)
                            t('strings.unlockingAtHeight', {'number': n['requested_unlock_height']}),
                        ].join(' · '),
                        action: _int(n['requested_unlock_height']) > 0
                            ? null
                            : TextButton(onPressed: () => _unlock(n), child: Text(t('buttons.unlock'))),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Deregistered stakes',
          trailing: TextButton(onPressed: _checkDeregistered, child: Text(t('buttons.check'))),
          child: _deregistered == null
              ? const SizedBox.shrink()
              : _deregistered!.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('None of your stakes are deregistered.'))
              : Column(
                  children: [
                    for (final d in _deregistered!)
                      DetailRow('${d['unlock_height'] ?? ''}', '${d['key_image']}', mono: true),
                  ],
                ),
        ),
      ],
    );
  }
}
