import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum NetType { mainnet, stagenet, testnet }

enum DaemonType {
  /// Use a remote node only.
  remote,

  /// Run beldexd locally.
  local,

  /// Run beldexd locally, bootstrapping from a remote node while it syncs.
  localRemote;

  String get configValue => this == localRemote ? 'local_remote' : name;

  static DaemonType parse(String? value) => switch (value) {
    'local' => local,
    'local_remote' => localRemote,
    _ => remote,
  };
}

class RemoteNode {
  const RemoteNode(this.host, this.port);
  final String host;
  final int port;
  @override
  String toString() => '$host:$port';
}

/// Public nodes offered in settings and used for automatic failover.
const knownRemotes = <RemoteNode>[
  RemoteNode('mainnet.beldex.io', 29095),
  RemoteNode('publicnode1.rpcnode.stream', 29095),
  RemoteNode('publicnode2.rpcnode.stream', 29095),
  RemoteNode('publicnode3.rpcnode.stream', 29095),
  RemoteNode('publicnode4.rpcnode.stream', 29095),
  RemoteNode('publicnode5.rpcnode.stream', 29095),
];

class DaemonConfig {
  DaemonConfig({
    required this.type,
    required this.remoteHost,
    required this.remotePort,
    required this.p2pBindPort,
    required this.rpcBindPort,
    this.p2pBindIp = '0.0.0.0',
    this.rpcBindIp = '127.0.0.1',
    this.outPeers = -1,
    this.inPeers = -1,
    this.limitRateUp = -1,
    this.limitRateDown = -1,
    this.logLevel = 0,
  });

  DaemonType type;
  String remoteHost;
  int remotePort;
  String p2pBindIp;
  int p2pBindPort;
  String rpcBindIp;
  int rpcBindPort;
  int outPeers;
  int inPeers;
  int limitRateUp;
  int limitRateDown;
  int logLevel;

  bool get runsLocally => type != DaemonType.remote;

  Map<String, dynamic> toJson() => {
    'type': type.configValue,
    'remote_host': remoteHost,
    'remote_port': remotePort,
    'p2p_bind_ip': p2pBindIp,
    'p2p_bind_port': p2pBindPort,
    'rpc_bind_ip': rpcBindIp,
    'rpc_bind_port': rpcBindPort,
    'out_peers': outPeers,
    'in_peers': inPeers,
    'limit_rate_up': limitRateUp,
    'limit_rate_down': limitRateDown,
    'log_level': logLevel,
  };

  factory DaemonConfig.fromJson(Map<String, dynamic> j, DaemonConfig d) => DaemonConfig(
    type: DaemonType.parse(j['type'] as String? ?? d.type.configValue),
    remoteHost: j['remote_host'] as String? ?? d.remoteHost,
    remotePort: (j['remote_port'] as num?)?.toInt() ?? d.remotePort,
    p2pBindIp: j['p2p_bind_ip'] as String? ?? d.p2pBindIp,
    p2pBindPort: (j['p2p_bind_port'] as num?)?.toInt() ?? d.p2pBindPort,
    rpcBindIp: j['rpc_bind_ip'] as String? ?? d.rpcBindIp,
    rpcBindPort: (j['rpc_bind_port'] as num?)?.toInt() ?? d.rpcBindPort,
    outPeers: (j['out_peers'] as num?)?.toInt() ?? d.outPeers,
    inPeers: (j['in_peers'] as num?)?.toInt() ?? d.inPeers,
    limitRateUp: (j['limit_rate_up'] as num?)?.toInt() ?? d.limitRateUp,
    limitRateDown: (j['limit_rate_down'] as num?)?.toInt() ?? d.limitRateDown,
    logLevel: (j['log_level'] as num?)?.toInt() ?? d.logLevel,
  );

  DaemonConfig copy() => DaemonConfig.fromJson(toJson(), this);

  static DaemonConfig defaults(NetType net) => switch (net) {
    NetType.mainnet => DaemonConfig(
      type: DaemonType.remote,
      remoteHost: knownRemotes.first.host,
      remotePort: knownRemotes.first.port,
      p2pBindPort: 19090,
      rpcBindPort: 19091,
    ),
    NetType.stagenet => DaemonConfig(
      type: DaemonType.local,
      remoteHost: '',
      remotePort: 0,
      p2pBindPort: 29090,
      rpcBindPort: 29091,
    ),
    NetType.testnet => DaemonConfig(
      type: DaemonType.local,
      remoteHost: '',
      remotePort: 0,
      p2pBindPort: 39090,
      rpcBindPort: 39091,
    ),
  };
}

/// Persistent app configuration. Stored as JSON in the platform's
/// application-support directory, separate from the Electron wallet's
/// config; blockchain and wallet directories default to the same places
/// so both apps can share wallets.
class AppConfig {
  AppConfig({
    required this.netType,
    required this.dataDir,
    required this.walletDataDir,
    required this.daemons,
    this.walletRpcPort = 29296,
    this.walletLogLevel = 0,
    this.language = 'en-us',
    this.darkTheme = true,
    this.autoLockMinutes = 15,
    this.hideBalance = false,
    this.askPasswordOnSend = false,
    this.showFiat = true,
    this.lastWallet = '',
  });

  NetType netType;
  String dataDir;
  String walletDataDir;
  Map<NetType, DaemonConfig> daemons;
  int walletRpcPort;
  int walletLogLevel;
  String language;
  bool darkTheme;

  /// Lock the UI after this many idle minutes (0 = never).
  int autoLockMinutes;
  bool hideBalance;
  bool askPasswordOnSend;
  bool showFiat;

  /// Wallet shown first on the unlock screen.
  String lastWallet;

  DaemonConfig get daemon => daemons[netType]!;

  static String get _home => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

  static String defaultDataDir() => Platform.isWindows ? r'C:\ProgramData\beldex' : p.join(_home, '.beldex');

  static String defaultWalletDir() =>
      Platform.isWindows ? p.join(_home, 'Documents', 'Beldex') : p.join(_home, 'Beldex');

  factory AppConfig.defaults() => AppConfig(
    netType: NetType.mainnet,
    dataDir: defaultDataDir(),
    walletDataDir: defaultWalletDir(),
    daemons: {for (final n in NetType.values) n: DaemonConfig.defaults(n)},
  );

  /// Directory holding blockchain data/logs for the current network.
  String get netDataDir => switch (netType) {
    NetType.mainnet => dataDir,
    NetType.stagenet => p.join(dataDir, 'stagenet'),
    NetType.testnet => p.join(dataDir, 'testnet'),
  };

  /// Directory holding wallet files for the current network.
  String get walletDir => switch (netType) {
    NetType.mainnet => p.join(walletDataDir, 'wallets'),
    NetType.stagenet => p.join(walletDataDir, 'stagenet', 'wallets'),
    NetType.testnet => p.join(walletDataDir, 'testnet', 'wallets'),
  };

  String get logDir => p.join(netDataDir, 'logs');

  Map<String, dynamic> toJson() => {
    'net_type': netType.name,
    'data_dir': dataDir,
    'wallet_data_dir': walletDataDir,
    'daemons': {for (final e in daemons.entries) e.key.name: e.value.toJson()},
    'wallet_rpc_port': walletRpcPort,
    'wallet_log_level': walletLogLevel,
    'language': language,
    'dark_theme': darkTheme,
    'auto_lock_minutes': autoLockMinutes,
    'hide_balance': hideBalance,
    'ask_password_on_send': askPasswordOnSend,
    'show_fiat': showFiat,
    'last_wallet': lastWallet,
  };

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final d = AppConfig.defaults();
    final daemonsJson = (j['daemons'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppConfig(
      netType: NetType.values.asNameMap()[j['net_type']] ?? d.netType,
      dataDir: _nonEmpty(j['data_dir']) ?? d.dataDir,
      walletDataDir: _nonEmpty(j['wallet_data_dir']) ?? d.walletDataDir,
      daemons: {
        for (final n in NetType.values)
          n: daemonsJson[n.name] is Map
              ? DaemonConfig.fromJson((daemonsJson[n.name] as Map).cast<String, dynamic>(), d.daemons[n]!)
              : d.daemons[n]!,
      },
      walletRpcPort: (j['wallet_rpc_port'] as num?)?.toInt() ?? d.walletRpcPort,
      walletLogLevel: (j['wallet_log_level'] as num?)?.toInt() ?? d.walletLogLevel,
      language: j['language'] as String? ?? d.language,
      darkTheme: j['dark_theme'] as bool? ?? d.darkTheme,
      autoLockMinutes: (j['auto_lock_minutes'] as num?)?.toInt() ?? d.autoLockMinutes,
      hideBalance: j['hide_balance'] as bool? ?? d.hideBalance,
      askPasswordOnSend: j['ask_password_on_send'] as bool? ?? d.askPasswordOnSend,
      showFiat: j['show_fiat'] as bool? ?? d.showFiat,
      lastWallet: j['last_wallet'] as String? ?? d.lastWallet,
    );
  }

  AppConfig copy() => AppConfig.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  static String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'config.json'));
  }

  /// Returns null when no config exists yet (first run).
  static Future<AppConfig?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      return AppConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    await tmp.rename(file.path);
  }
}
