import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config.dart';
import '../../../core/i18n.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Edits network/daemon/storage settings of an [AppConfig] in place.
class NodeSettingsForm extends StatefulWidget {
  const NodeSettingsForm({super.key, required this.config, this.onChanged});
  final AppConfig config;
  final VoidCallback? onChanged;

  @override
  State<NodeSettingsForm> createState() => _NodeSettingsFormState();
}

class _NodeSettingsFormState extends State<NodeSettingsForm> {
  AppConfig get c => widget.config;
  DaemonConfig get d => c.daemon;

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isRemote = d.type == DaemonType.remote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('fieldLabels.chooseNetwork'), style: const TextStyle(color: BeldexColors.muted)),
        const SizedBox(height: 8),
        SegmentedButton<NetType>(
          segments: [for (final n in NetType.values) ButtonSegment(value: n, label: Text(netLabel(n)))],
          selected: {c.netType},
          onSelectionChanged: (s) => _update(() => c.netType = s.first),
        ),
        const SizedBox(height: 20),
        SegmentedButton<DaemonType>(
          segments: [
            ButtonSegment(value: DaemonType.remote, label: Text(t('strings.daemon.remote.title'))),
            ButtonSegment(value: DaemonType.localRemote, label: Text(t('strings.daemon.localRemote.title'))),
            ButtonSegment(value: DaemonType.local, label: Text(t('strings.daemon.local.title'))),
          ],
          selected: {d.type},
          onSelectionChanged: (s) => _update(() => d.type = s.first),
        ),
        const SizedBox(height: 8),
        Text(switch (d.type) {
          DaemonType.remote => t('strings.daemon.remote.description'),
          DaemonType.localRemote => t('strings.daemon.localRemote.description'),
          DaemonType.local => t('strings.daemon.local.description'),
        }, style: const TextStyle(color: BeldexColors.muted, fontSize: 12)),
        const SizedBox(height: 20),
        if (d.type != DaemonType.local) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _text(t('fieldLabels.remoteNodeHost'), d.remoteHost, (v) => d.remoteHost = v.trim()),
              ),
              const SizedBox(width: 12),
              Expanded(child: _int(t('fieldLabels.remoteNodePort'), d.remotePort, (v) => d.remotePort = v)),
              const SizedBox(width: 8),
              PopupMenuButton<RemoteNode>(
                tooltip: 'Public nodes',
                icon: const Icon(Icons.list),
                itemBuilder: (_) => [for (final r in knownRemotes) PopupMenuItem(value: r, child: Text('$r'))],
                onSelected: (r) => _update(() {
                  d.remoteHost = r.host;
                  d.remotePort = r.port;
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (!isRemote) ...[
          Row(
            children: [
              Expanded(
                child: _text(
                  t('fieldLabels.localDaemonIP'),
                  d.rpcBindIp,
                  (v) => d.rpcBindIp = v.trim(),
                  enabled: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _int(t('fieldLabels.localDaemonPort'), d.rpcBindPort, (v) => d.rpcBindPort = v)),
              const SizedBox(width: 12),
              Expanded(child: _int(t('fieldLabels.daemonP2pPort'), d.p2pBindPort, (v) => d.p2pBindPort = v)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _int(t('fieldLabels.maxIncomingPeers'), d.inPeers, (v) => d.inPeers = v, signed: true)),
              const SizedBox(width: 12),
              Expanded(child: _int(t('fieldLabels.maxOutgoingPeers'), d.outPeers, (v) => d.outPeers = v, signed: true)),
              const SizedBox(width: 12),
              Expanded(
                child: _int(t('fieldLabels.limitUploadRate'), d.limitRateUp, (v) => d.limitRateUp = v, signed: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _int(
                  t('fieldLabels.limitDownloadRate'),
                  d.limitRateDown,
                  (v) => d.limitRateDown = v,
                  signed: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _dir(t('fieldLabels.dataStoragePath'), c.dataDir, (v) => c.dataDir = v),
          const SizedBox(height: 16),
        ],
        _dir(t('fieldLabels.walletStoragePath'), c.walletDataDir, (v) => c.walletDataDir = v),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('strings.advancedOptions')),
          children: [
            Row(
              children: [
                Expanded(child: _int(t('fieldLabels.walletRPCPort'), c.walletRpcPort, (v) => c.walletRpcPort = v)),
                const SizedBox(width: 12),
                Expanded(child: _int(t('fieldLabels.daemonLogLevel'), d.logLevel, (v) => d.logLevel = v)),
                const SizedBox(width: 12),
                Expanded(child: _int(t('fieldLabels.walletLogLevel'), c.walletLogLevel, (v) => c.walletLogLevel = v)),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  Widget _text(String label, String value, void Function(String) onChanged, {bool enabled = true}) => TextFormField(
    key: ValueKey('$label-${c.netType}'),
    initialValue: value,
    enabled: enabled,
    decoration: InputDecoration(labelText: label),
    onChanged: (v) {
      onChanged(v);
      widget.onChanged?.call();
    },
  );

  Widget _int(String label, int value, void Function(int) onChanged, {bool signed = false}) => TextFormField(
    key: ValueKey('$label-${c.netType}'),
    initialValue: '$value',
    decoration: InputDecoration(labelText: label),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(signed ? r'^-?\d*' : r'^\d*'))],
    onChanged: (v) {
      final parsed = int.tryParse(v);
      if (parsed != null) {
        onChanged(parsed);
        widget.onChanged?.call();
      }
    },
  );

  Widget _dir(String label, String value, void Function(String) onChanged) => Row(
    children: [
      Expanded(
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(value, overflow: TextOverflow.ellipsis),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () async {
          final dir = await getDirectoryPath(initialDirectory: value, confirmButtonText: t('buttons.selectLocation'));
          if (dir != null) _update(() => onChanged(dir));
        },
        child: Text(t('buttons.browse')),
      ),
    ],
  );
}
