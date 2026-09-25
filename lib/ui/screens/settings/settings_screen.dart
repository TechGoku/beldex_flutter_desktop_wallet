import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../core/i18n.dart';
import '../../../services/daemon_service.dart';
import '../../../state/app_controller.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'node_settings_form.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.startupMode = false});

  /// Opened from the startup failure screen: saving restarts services.
  final bool startupMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppConfig _pending;

  @override
  void initState() {
    super.initState();
    _pending = context.read<AppController>().config.copy();
  }

  Future<void> _save() async {
    final app = context.read<AppController>();
    final navigator = Navigator.of(context);
    if (widget.startupMode) {
      navigator.pop();
      await app.saveConfigAndStart(_pending.copy());
      return;
    }
    // A new node on the same network is switched to live (the wallet stays
    // open); only network or folder changes need a restart.
    final needsRestart = await runWithProgress(
      context,
      () => app.saveSettings(_pending.copy()),
      message: 'Connecting to the node…',
    );
    // null: the node didn't answer (already reported); nothing changed
    if (needsRestart == null || !mounted) return;
    if (needsRestart) {
      final restart = await confirmDialog(
        context,
        title: t('dialog.restart.title'),
        message: t('dialog.restart.message'),
        okLabel: t('dialog.restart.ok'),
      );
      if (restart) {
        navigator.pop();
        await app.shutdown();
        await app.saveConfigAndStart(app.config);
        return;
      }
    } else {
      app.notify('Now using ${_nodeLabel(app.config)}');
    }
    navigator.pop();
  }

  static String _nodeLabel(AppConfig c) => switch (c.daemon.type) {
    DaemonType.remote => '${c.daemon.remoteHost}:${c.daemon.remotePort}',
    DaemonType.local => 'your local node',
    DaemonType.localRemote => 'your local node (with ${c.daemon.remoteHost} while it syncs)',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final showPeers = app.config.daemon.runsLocally && !widget.startupMode;
    return DefaultTabController(
      length: showPeers ? 3 : 2,
      child: BScaffold(
        body: SubPage(
          title: t('titles.settings.title'),
          onBack: () => Navigator.maybePop(context),
          maxWidth: 640,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: t('titles.settings.tabs.general')),
                        Tab(text: t('titles.settings.tabs.language')),
                        if (showPeers) Tab(text: t('titles.settings.tabs.peers')),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            NodeSettingsForm(config: _pending),
                            const SizedBox(height: 16),
                            PrimaryButton(t('buttons.save'), onPressed: _save),
                          ],
                        ),
                        const _LanguageTab(),
                        if (showPeers) const _PeersTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTab extends StatelessWidget {
  const _LanguageTab();

  @override
  Widget build(BuildContext context) {
    final current = context.select<I18n, String>((i) => i.locale);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        for (final lang in languages)
          MenuRow(
            label: lang.name,
            trailing: current == lang.code
                ? const Icon(Icons.check, color: BeldexColors.green, size: 18)
                : const SizedBox.shrink(),
            onTap: () => context.read<AppController>().setLanguage(lang.code),
          ),
      ],
    );
  }
}

class _PeersTab extends StatelessWidget {
  const _PeersTab();

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<DaemonService>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(t('strings.peerList'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final peer in daemon.connections)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('${peer['address'] ?? peer['host']}'),
              subtitle: Text('Height ${peer['height'] ?? '-'} · ${peer['incoming'] == true ? 'in' : 'out'}'),
              trailing: TextButton(
                onPressed: () => _ban(context, '${peer['host']}'),
                child: Text(t('dialog.banPeer.ok')),
              ),
            ),
          ),
        if (daemon.bans.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(t('strings.bannedPeers.title'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final ban in daemon.bans)
            ListTile(
              dense: true,
              title: Text('${ban['host']}'),
              subtitle: Text(
                t('strings.bannedPeers.bannedUntil', {
                  'time': DateTime.now().add(Duration(seconds: (ban['seconds'] as num?)?.toInt() ?? 0)).toString(),
                }),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _ban(BuildContext context, String host) async {
    final controller = TextEditingController(text: '3600');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('dialog.banPeer.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('dialog.banPeer.message')),
            const SizedBox(height: 12),
            TextField(controller: controller, keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('dialog.buttons.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BeldexColors.negative),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('dialog.banPeer.ok')),
          ),
        ],
      ),
    );
    final seconds = int.tryParse(controller.text) ?? 3600;
    controller.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await context.read<DaemonService>().banPeer(host, seconds);
      if (context.mounted) {
        showSnack(context, t('notification.positive.bannedPeer', {'host': host, 'time': '$seconds s'}));
      }
    } catch (e) {
      if (context.mounted) showSnack(context, t('notification.errors.banningPeer'), error: true);
    }
  }
}
