import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/config.dart';
import '../core/password_hash.dart';
import '../core/rpc_client.dart';
import 'binaries.dart';
import 'daemon_service.dart';
import 'models.dart';

/// Runs beldex-wallet-rpc and exposes the open wallet's state.
///
/// Sync design (same as the optimised Electron wallet):
///  * wallet-rpc refreshes inside its only request thread and otherwise
///    waits 20 s between refreshes, so on open we trigger `refresh` at once
///    and lower the auto-refresh period to 10 s;
///  * the heartbeat only polls cheap calls (height, balance);
///  * history, subaddresses and the address book are refreshed when the
///    balance changes, deferred while the wallet is still scanning, and
///    transfers are fetched incrementally by height.
class WalletService extends ChangeNotifier {
  WalletService(this.daemon);

  final DaemonService daemon;
  late AppConfig _config;
  JsonRpcClient? _rpc;
  Process? _process;
  final _passwords = PasswordHasher();

  // ---- open wallet state -------------------------------------------------
  bool isOpen = false;
  String name = '';
  String address = '';
  int height = 0;
  int balance = 0;
  int unlockedBalance = 0;
  bool viewOnly = false;
  bool balanceLoading = false;

  List<Transfer> transfers = const [];
  List<SubAddress> primaryAddresses = const [];
  List<SubAddress> usedAddresses = const [];
  List<SubAddress> unusedAddresses = const [];
  List<AddressBookEntry> addressBook = const [];
  List<BnsRecord> bnsRecords = const [];

  WalletList walletList = WalletList();

  // ---- sync tracking --------------------------------------------------------
  int? scanHeight; // from wallet-rpc progress output while scanning
  DateTime _lastSyncLine = DateTime.fromMillisecondsSinceEpoch(0);
  bool _rpcSyncing = false;
  Timer? _heartbeat;
  Timer? _bnsHeartbeat;
  bool _heartbeatInFlight = false;
  bool _historyRefreshPending = false;
  DateTime _lastHistoryRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  // Incremental transfer cache
  List<Transfer> _confirmed = [];
  List<Transfer> _transient = [];
  int _maxConfirmedHeight = 0;
  bool _transfersLoaded = false;
  String? _transferFingerprint;
  String? _addressFingerprint;
  String? _bookFingerprint;

  final Set<String> _validAddresses = {};
  final Map<String, Future<bool>> _addressChecks = {};

  static final _progressPatterns = [
    RegExp(r'Processed block: <([a-f0-9]+)>, height (\d+)'),
    RegExp(r'Skipped block by height: (\d+)'),
    RegExp(r'Skipped block by timestamp, height: (\d+)'),
    RegExp(r'Blockchain sync progress: <([a-f0-9]+)>, height (\d+)'),
  ];

  String get walletDir => _config.walletDir;

  /// False until the first transfer list has been fetched (drives skeletons).
  bool get historyLoaded => _transfersLoaded;
  NetType get netType => _config.netType;

  /// True while wallet-rpc is scanning blocks it hasn't seen yet.
  bool get isSyncing {
    if (_rpcSyncing) return true;
    final daemonHeight = daemon.info.height;
    if (daemonHeight == 0 || height == 0) return false;
    return height < daemonHeight - 2;
  }

  // ======================================================================
  // Process management
  // ======================================================================

  Future<void> start(AppConfig config) async {
    _config = config;
    final binary = Binaries.walletRpc;
    if (binary == null) {
      throw StateError('Failed to find Beldex Wallet RPC. Please make sure your anti-virus has not removed it.');
    }
    // A wallet-rpc left over from an earlier session may hold the port; its
    // credentials are unknown, so run ours on the next free port instead.
    var port = config.walletRpcPort;
    while (!await isPortFree(port)) {
      if (++port > config.walletRpcPort + 200) {
        throw StateError('Wallet RPC port ${config.walletRpcPort} is in use');
      }
    }
    await Directory(config.walletDir).create(recursive: true);
    await Directory(config.logDir).create(recursive: true);
    final logFile = File(p.join(config.logDir, 'wallet-rpc.log'));
    if (await logFile.exists()) await logFile.writeAsString('');

    final user = randomHex(32);
    final pass = randomHex(32);
    final d = config.daemon;
    final daemonAddress = d.type == DaemonType.remote
        ? '${d.remoteHost}:${d.remotePort}'
        : '${d.rpcBindIp}:${d.rpcBindPort}';
    final args = [
      '--rpc-login',
      '$user:$pass',
      '--rpc-bind-port',
      '$port',
      '--rpc-bind-ip',
      '127.0.0.1',
      '--daemon-address',
      daemonAddress,
      '--log-level',
      '${config.walletLogLevel}',
      '--log-file',
      logFile.path,
      '--wallet-dir',
      config.walletDir,
      '--trusted-daemon',
      if (config.netType == NetType.testnet) '--testnet',
      if (config.netType == NetType.stagenet) '--stagenet',
    ];

    _rpc = JsonRpcClient(endpoint: Uri.parse('http://127.0.0.1:$port/json_rpc'), username: user, password: pass);
    _process = await Process.start(binary, args);
    final exited = Completer<int>();
    _process!.exitCode.then((code) {
      _process = null;
      if (!exited.isCompleted) exited.complete(code);
    });
    _process!.stdout.transform(utf8.decoder).listen(_onOutput);
    _process!.stderr.transform(utf8.decoder).listen((_) {});

    while (true) {
      if (exited.isCompleted) {
        throw StateError('Failed to start wallet RPC (exit code ${await exited.future})');
      }
      try {
        await _rpc!.call('get_languages', timeout: const Duration(seconds: 5));
        return;
      } on RpcError catch (e) {
        if (!e.isConnectionRefused && e.code != -1) rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  void _onOutput(String data) {
    int? latest;
    for (final line in data.split('\n')) {
      for (final pattern in _progressPatterns) {
        final m = pattern.firstMatch(line);
        if (m != null) {
          latest = int.tryParse(m.group(m.groupCount)!);
          break;
        }
      }
    }
    if (latest != null) {
      _lastSyncLine = DateTime.now();
      scanHeight = latest;
      if (latest > height) {
        height = latest;
        notifyListeners();
      }
    }
    _updateSyncingFlag();
  }

  void _updateSyncingFlag() {
    // At log level 0 wallet-rpc prints progress every 2000 blocks
    final syncing = DateTime.now().difference(_lastSyncLine) < const Duration(seconds: 45);
    if (syncing != _rpcSyncing) {
      _rpcSyncing = syncing;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _bnsHeartbeat?.cancel();
    if (isOpen) {
      try {
        await closeWallet();
      } catch (_) {}
    }
    final proc = _process;
    if (proc != null) {
      // A syncing wallet-rpc can take long to stop gracefully
      proc.kill(_rpcSyncing ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      await proc.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    _rpc?.close();
  }

  Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? params, Duration? timeout]) async {
    final rpc = _rpc;
    if (rpc == null) throw WalletException.i18n('notification.errors.unknownError');
    try {
      return await rpc.call(method, params: params, timeout: timeout);
    } on RpcError catch (e) {
      throw WalletException.message(e.displayMessage);
    }
  }

  // ======================================================================
  // Wallet files
  // ======================================================================

  static const _ignoredFiles = {
    '.DS_Store',
    '.DS_Store?',
    '._.DS_Store',
    '.Spotlight-V100',
    '.Trashes',
    'ehthumbs.db',
    'Thumbs.db',
    'old-gui',
  };

  Future<WalletList> listWallets({bool includeLegacy = false}) async {
    final dir = Directory(walletDir);
    final wallets = <WalletFileInfo>[];
    final oldGui = <String>[];
    if (await dir.exists()) {
      final entries = await dir.list(followLinks: false).toList();
      final names = entries.map((e) => p.basename(e.path)).toSet();
      await Future.wait(
        entries.map((entry) async {
          final filename = p.basename(entry.path);
          if (_ignoredFiles.contains(filename)) return;
          if (entry is Directory) {
            if (await File(p.join(entry.path, '$filename.keys')).exists()) oldGui.add(filename);
            return;
          }
          if (p.extension(filename) != '.keys') return;
          final walletName = p.basenameWithoutExtension(filename);
          if (walletName.isEmpty) return;
          String? addr;
          bool? protected;
          try {
            if (names.contains('$walletName.meta.json')) {
              final meta = jsonDecode(await File(p.join(walletDir, '$walletName.meta.json')).readAsString());
              addr = meta['address'] as String?;
              protected = meta['password_protected'] as bool?;
            } else if (names.contains('$walletName.address.txt')) {
              addr = (await File(p.join(walletDir, '$walletName.address.txt')).readAsString()).trim();
            }
          } catch (_) {}
          wallets.add(WalletFileInfo(name: walletName, address: addr, passwordProtected: protected));
        }),
      );
    }
    wallets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    oldGui.sort();

    final legacy = <LegacyWallet>[];
    if (includeLegacy) {
      final base = Platform.isWindows ? r'C:\ProgramData\Beldex' : AppConfig.defaultWalletDir();
      final info = File(
        _config.netType == NetType.testnet
            ? p.join(base, 'testnet', 'config', 'wallet_info.json')
            : p.join(base, 'config', 'wallet_info.json'),
      );
      try {
        if (await info.exists()) {
          final path = (jsonDecode(await info.readAsString()) as Map)['wallet_filepath'] as String;
          if (await File(path).exists()) {
            final addrFile = File('$path.address.txt');
            legacy.add(LegacyWallet(path, await addrFile.exists() ? await addrFile.readAsString() : ''));
          }
        }
      } catch (_) {}
    }

    walletList = WalletList(wallets: wallets, oldGuiDirectories: oldGui, legacy: legacy);
    notifyListeners();
    return walletList;
  }

  /// Moves old-GUI style wallet folders (`<name>/<name>.keys`) into the
  /// flat wallet directory. Returns the directories that failed.
  Future<List<String>> importOldGuiWallets(Map<String, NetType> directories) async {
    final failed = <String>[];
    final archive = Directory(p.join(walletDir, 'old-gui'));
    for (final entry in directories.entries) {
      final dirName = entry.key;
      final source = Directory(p.join(walletDir, dirName));
      final destination = switch (entry.value) {
        NetType.mainnet => p.join(_config.walletDataDir, 'wallets'),
        NetType.stagenet => p.join(_config.walletDataDir, 'stagenet', 'wallets'),
        NetType.testnet => p.join(_config.walletDataDir, 'testnet', 'wallets'),
      };
      try {
        if (!await File(p.join(source.path, '$dirName.keys')).exists() ||
            await File(p.join(destination, '$dirName.keys')).exists()) {
          failed.add(dirName);
          continue;
        }
        await Directory(destination).create(recursive: true);
        await archive.create(recursive: true);
        final archived = await source.rename(p.join(archive.path, dirName));
        await for (final f in archived.list()) {
          if (f is File) await f.copy(p.join(destination, p.basename(f.path)));
        }
      } catch (_) {
        failed.add(dirName);
      }
    }
    await listWallets();
    return failed;
  }

  // ======================================================================
  // Opening / creating wallets
  // ======================================================================

  /// Creates a wallet and returns its secrets so they can be shown once.
  Future<WalletSecrets> createWallet(String name, String password, String language) async {
    await _call('create_wallet', {'filename': name, 'password': password, 'language': language});
    return _afterOpen(name, password, revealSecrets: true);
  }

  Future<WalletSecrets> restoreFromSeed(String name, String password, String seed, int restoreHeight) async {
    await _call('restore_deterministic_wallet', {
      'filename': name,
      'password': password,
      'seed': seed.trim().replaceAll(RegExp(r'\s+'), ' '),
      'restore_height': restoreHeight,
    });
    return _afterOpen(name, password, revealSecrets: true);
  }

  Future<WalletSecrets> restoreFromKeys(
    String name,
    String password, {
    required String address,
    required String viewKey,
    String spendKey = '',
    required int restoreHeight,
  }) async {
    await _call('generate_from_keys', {
      'filename': name,
      'password': password,
      'address': address,
      'viewkey': viewKey,
      if (spendKey.isNotEmpty) 'spendkey': spendKey,
      'restore_height': restoreHeight,
    });
    return _afterOpen(name, password, revealSecrets: true);
  }

  Future<WalletSecrets> restoreViewOnly(
    String name,
    String password, {
    required String address,
    required String viewKey,
    required int restoreHeight,
  }) async {
    await _call('restore_view_wallet', {
      'filename': name,
      'password': password,
      'address': address,
      'viewkey': viewKey,
      'refresh_start_height': restoreHeight,
    });
    return _afterOpen(name, password, revealSecrets: true);
  }

  /// Converts a restore date to a block height (a day earlier, to be safe).
  Future<int> heightForDate(DateTime date) async {
    final dayStart = DateTime.utc(date.year, date.month, date.day).subtract(const Duration(days: 1));
    final h = await daemon.timestampToHeight(dayStart.millisecondsSinceEpoch ~/ 1000);
    if (h == null) throw WalletException.i18n('notification.errors.invalidRestoreDate');
    return h;
  }

  Future<WalletSecrets> importWallet(String name, String password, String path) async {
    var source = path;
    if (source.endsWith('.keys')) source = source.substring(0, source.length - 5);
    if (source.endsWith('.address.txt')) source = source.substring(0, source.length - 12);
    if (!await File(source).exists() && !await File('$source.keys').exists()) {
      throw WalletException.i18n('notification.errors.invalidWalletPath');
    }
    final dest = p.join(walletDir, name);
    if (await File(dest).exists() || await File('$dest.keys').exists()) {
      throw WalletException.i18n('notification.errors.walletAlreadyExists');
    }
    try {
      if (await File(source).exists()) await File(source).copy(dest);
      if (await File('$source.keys').exists()) await File('$source.keys').copy('$dest.keys');
    } catch (_) {
      throw WalletException.i18n('notification.errors.copyWalletFail');
    }
    try {
      await _call('open_wallet', {'filename': name, 'password': password});
    } catch (e) {
      for (final f in [dest, '$dest.keys']) {
        if (await File(f).exists()) await File(f).delete();
      }
      rethrow;
    }
    return _afterOpen(name, password, revealSecrets: true);
  }

  Future<void> openWallet(String name, String password) async {
    await _call('open_wallet', {'filename': name, 'password': password});
    await _afterOpen(name, password, revealSecrets: false);
  }

  Future<WalletSecrets> _afterOpen(String walletName, String password, {required bool revealSecrets}) async {
    await _passwords.remember(password);
    _resetState();
    isOpen = true;
    name = walletName;

    final results = await Future.wait([
      _safeCall('get_address', {'account_index': 0}),
      _safeCall('getheight'),
      _safeCall('getbalance', {'account_index': 0}),
      _safeCall('query_key', {'key_type': 'spend_key'}),
      if (revealSecrets) _safeCall('query_key', {'key_type': 'mnemonic'}),
      if (revealSecrets) _safeCall('query_key', {'key_type': 'view_key'}),
    ]);
    address = results[0]?['address'] as String? ?? '';
    height = (results[1]?['height'] as num?)?.toInt() ?? 0;
    balance = (results[2]?['balance'] as num?)?.toInt() ?? 0;
    unlockedBalance = (results[2]?['unlocked_balance'] as num?)?.toInt() ?? 0;
    final spendKey = results[3]?['key'] as String?;
    viewOnly = spendKey == null || RegExp(r'^0*$').hasMatch(spendKey);

    final addressTxt = File(p.join(walletDir, '$walletName.address.txt'));
    if (address.isNotEmpty && !await addressTxt.exists()) {
      await addressTxt.writeAsString(address);
    }
    unawaited(_safeCall('store'));
    unawaited(listWallets());

    _startHeartbeat();
    notifyListeners();
    return WalletSecrets(
      mnemonic: revealSecrets ? (results[4]?['key'] as String? ?? '') : '',
      spendKey: revealSecrets && !viewOnly ? spendKey ?? '' : '',
      viewKey: revealSecrets ? (results[5]?['key'] as String? ?? '') : '',
    );
  }

  Future<Map<String, dynamic>?> _safeCall(String method, [Map<String, dynamic>? params, Duration? timeout]) async {
    try {
      return await _call(method, params, timeout);
    } catch (_) {
      return null;
    }
  }

  void _resetState() {
    isOpen = false;
    name = '';
    address = '';
    height = 0;
    balance = 0;
    unlockedBalance = 0;
    viewOnly = false;
    scanHeight = null;
    transfers = const [];
    primaryAddresses = const [];
    usedAddresses = const [];
    unusedAddresses = const [];
    addressBook = const [];
    bnsRecords = const [];
    _confirmed = [];
    _transient = [];
    _maxConfirmedHeight = 0;
    _transfersLoaded = false;
    _transferFingerprint = null;
    _addressFingerprint = null;
    _bookFingerprint = null;
    _historyRefreshPending = false;
    _lastHistoryRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> closeWallet() async {
    _heartbeat?.cancel();
    _bnsHeartbeat?.cancel();
    _passwords.forget();
    _resetState();
    notifyListeners();
    await _safeCall('store');
    await _safeCall('close_wallet');
  }

  // ======================================================================
  // Heartbeat & sync
  // ======================================================================

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 8), (_) => _heartbeatTick());
    _historyRefreshPending = true;
    _heartbeatTick(initial: true);
    _startSync();
    _bnsHeartbeat?.cancel();
    _bnsHeartbeat = Timer.periodic(const Duration(seconds: 80), (_) {
      if (!isSyncing) refreshBnsRecords();
    });
  }

  void _startSync() {
    unawaited(_safeCall('auto_refresh', {'enable': true, 'period': 10}));
    _safeCall('refresh').then((r) async {
      if (r == null) return;
      _lastSyncLine = DateTime.fromMillisecondsSinceEpoch(0);
      _updateSyncingFlag();
      final h = await _safeCall('getheight', null, const Duration(seconds: 5));
      final newHeight = (h?['height'] as num?)?.toInt();
      if (newHeight != null && newHeight != height) {
        height = newHeight;
        notifyListeners();
      }
      unawaited(refreshBnsRecords());
    });
  }

  Future<void> _heartbeatTick({bool initial = false}) async {
    if (_heartbeatInFlight && !initial) return;
    _heartbeatInFlight = true;
    try {
      const t = Duration(seconds: 5);
      final results = await Future.wait([
        _safeCall('getheight', null, t),
        _safeCall('getbalance', {'account_index': 0}, t),
      ]);
      if (!isOpen) return;
      var changed = false;
      final h = (results[0]?['height'] as num?)?.toInt();
      if (h != null && h != height) {
        height = h;
        changed = true;
      }
      final b = results[1];
      if (b != null) {
        final newBalance = (b['balance'] as num?)?.toInt() ?? 0;
        final newUnlocked = (b['unlocked_balance'] as num?)?.toInt() ?? 0;
        if (newBalance != balance || newUnlocked != unlockedBalance) {
          balance = newBalance;
          unlockedBalance = newUnlocked;
          _historyRefreshPending = true;
          changed = true;
        }
      }
      _updateSyncingFlag();
      if (changed) notifyListeners();

      final refreshDue =
          initial || !isSyncing || DateTime.now().difference(_lastHistoryRefresh) > const Duration(seconds: 60);
      if (_historyRefreshPending && refreshDue) {
        _historyRefreshPending = false;
        await _refreshLists();
      }
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Future<void> _refreshLists({bool fullHistory = false}) async {
    _lastHistoryRefresh = DateTime.now();
    final results = await Future.wait([
      _refreshTransfers(full: fullHistory),
      _refreshAddresses(),
      refreshAddressBook(notify: false),
    ]);
    if (results.any((changed) => changed)) notifyListeners();
  }

  /// Manual "refresh balance" button: full reload.
  Future<void> refreshAll() async {
    balanceLoading = true;
    notifyListeners();
    try {
      final b = await _call('getbalance', {'account_index': 0});
      balance = (b['balance'] as num?)?.toInt() ?? 0;
      unlockedBalance = (b['unlocked_balance'] as num?)?.toInt() ?? 0;
      _transferFingerprint = null;
      _addressFingerprint = null;
      _bookFingerprint = null;
      await _refreshLists(fullHistory: true);
    } finally {
      balanceLoading = false;
      notifyListeners();
    }
  }

  /// Transfers are fetched incrementally: after the first load only entries
  /// at or above (newest confirmed height - 10) are requested (min_height is
  /// inclusive in wallet2), which also absorbs small reorgs.
  Future<bool> _refreshTransfers({bool full = false}) async {
    if (full) {
      _transfersLoaded = false;
      _transferFingerprint = null;
    }
    final minHeight = (_maxConfirmedHeight - 10).clamp(0, 1 << 62);
    final incremental = _transfersLoaded && minHeight > 0;
    final r = await _safeCall('get_transfers', {
      'in': true,
      'out': true,
      'pending': true,
      'failed': true,
      'pool': true,
      if (incremental) ...{'filter_by_height': true, 'min_height': minHeight, 'max_height': 500000000},
    });
    if (r == null || !isOpen) return false;

    final fetched = <Transfer>[];
    for (final type in const ['in', 'out', 'pending', 'failed', 'pool', 'miner', 'mnode', 'gov', 'stake', 'bns']) {
      final list = r[type];
      if (list is List) fetched.addAll(list.map((e) => Transfer((e as Map).cast<String, dynamic>())));
    }

    final confirmed = <String, Transfer>{};
    if (incremental) {
      for (final tx in _confirmed) {
        if (tx.height < minHeight) confirmed[tx.key] = tx;
      }
    }
    final transient = <Transfer>[];
    for (final tx in fetched) {
      if (tx.isPending) {
        transient.add(tx);
      } else {
        confirmed[tx.key] = tx;
      }
    }
    _confirmed = confirmed.values.toList();
    _transient = transient;
    _maxConfirmedHeight = _confirmed.fold(0, (m, tx) => tx.height > m ? tx.height : m);
    _transfersLoaded = true;

    final fingerprint =
        '${_confirmed.length}|${fetched.map((tx) => '${tx.key}:${tx.note}:${tx.confirmations}').join(',')}';
    if (fingerprint == _transferFingerprint) return false;
    _transferFingerprint = fingerprint;
    transfers = _sortedTransfers();
    return true;
  }

  List<Transfer> _sortedTransfers() =>
      List.unmodifiable([..._transient, ..._confirmed]..sort((a, b) => b.timestamp.compareTo(a.timestamp)));

  Future<bool> _refreshAddresses() async {
    final results = await Future.wait([
      _safeCall('get_address', {'account_index': 0}),
      _safeCall('getbalance', {'account_index': 0}),
    ]);
    final addrData = results[0];
    final balData = results[1];
    if (addrData == null || balData == null || !isOpen) return false;

    final perSub = <int, Map<String, dynamic>>{
      for (final s in (balData['per_subaddress'] as List? ?? const []))
        ((s as Map)['address_index'] as num).toInt(): s.cast<String, dynamic>(),
    };
    final primary = <SubAddress>[], used = <SubAddress>[], unused = <SubAddress>[];
    for (final a in (addrData['addresses'] as List? ?? const [])) {
      final raw = (a as Map).cast<String, dynamic>();
      final bal = perSub[(raw['address_index'] as num).toInt()];
      final sub = SubAddress({
        ...raw,
        'balance': bal?['balance'],
        'unlocked_balance': bal?['unlocked_balance'],
        'num_unspent_outputs': bal?['num_unspent_outputs'],
      });
      if (sub.index == 0) {
        primary.add(sub);
      } else if (sub.used) {
        used.add(sub);
      } else {
        unused.add(sub);
      }
    }
    // Keep 10 unused subaddresses available, like the Electron wallet
    final trimmed = unused.take(10).toList();
    while (trimmed.length < 10) {
      final created = await _safeCall('create_address', {'account_index': 0});
      if (created == null) break;
      trimmed.add(SubAddress({...created, 'address_index': created['address_index'], 'used': false}));
    }

    final fingerprint = jsonEncode([primary, used, trimmed].map((l) => l.map((s) => s.raw).toList()).toList());
    if (fingerprint == _addressFingerprint) return false;
    _addressFingerprint = fingerprint;
    primaryAddresses = primary;
    usedAddresses = used;
    unusedAddresses = trimmed;
    return true;
  }

  Future<bool> refreshAddressBook({bool notify = true}) async {
    final r = await _safeCall('get_address_book');
    if (r == null || !isOpen) return false;
    final entries =
        (r['entries'] as List? ?? const [])
            .map((e) => AddressBookEntry.fromRpc((e as Map).cast<String, dynamic>()))
            .toList()
          ..sort((a, b) {
            if (a.starred != b.starred) return a.starred ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final fingerprint = entries.map((e) => '${e.index}|${e.address}|${e.name}|${e.description}|${e.starred}').join(',');
    if (fingerprint == _bookFingerprint) return false;
    _bookFingerprint = fingerprint;
    addressBook = entries;
    if (notify) notifyListeners();
    return true;
  }

  Future<void> rescanBlockchain() async {
    _resetCaches();
    height = 0;
    notifyListeners();
    await _call('rescan_blockchain');
    _historyRefreshPending = true;
    unawaited(_heartbeatTick());
  }

  Future<void> rescanSpent() => _call('rescan_spent');

  void _resetCaches() {
    _confirmed = [];
    _transient = [];
    _maxConfirmedHeight = 0;
    _transfersLoaded = false;
    _transferFingerprint = null;
    transfers = const [];
  }

  // ======================================================================
  // Passwords & keys
  // ======================================================================

  Future<bool> hasPassword() => _passwords.hasPassword();

  /// Checks the open wallet's password (used by the lock screen).
  Future<bool> verifyPassword(String password) => _passwords.verify(password);

  /// Resolves a `name.bdx` BNS name to the wallet address it maps to.
  Future<String> resolveBns(String name) async {
    final full = fullBnsName(name);
    final hash = (await _call('bns_hash_name', {'name': full}))['name'] as String?;
    if (hash == null) throw WalletException.message('Could not hash BNS name');
    final record = await daemon.bnsRecord(hash);
    final encrypted = record?['encrypted_wallet_value'] as String?;
    if (encrypted == null || encrypted.isEmpty) {
      throw WalletException.message('$full has no wallet address');
    }
    final r = await _call('bns_decrypt_value', {'name': full, 'type': 'wallet', 'encrypted_value': encrypted});
    final address = r['value'] as String?;
    if (address == null || address.isEmpty) throw WalletException.message('Could not resolve $full');
    return address;
  }

  /// Creates a new labelled subaddress and returns it.
  Future<SubAddress> createSubaddress({String label = ''}) async {
    final r = await _call('create_address', {'account_index': 0, if (label.isNotEmpty) 'label': label});
    _addressFingerprint = null;
    await _refreshAddresses();
    notifyListeners();
    return SubAddress({...r, 'label': label, 'used': false});
  }

  Future<void> _requirePassword(String password) async {
    if (!await _passwords.verify(password)) {
      throw WalletException.i18n('notification.errors.invalidPassword');
    }
  }

  Future<WalletSecrets> privateKeys(String password) async {
    await _requirePassword(password);
    final r = await Future.wait([
      _safeCall('query_key', {'key_type': 'mnemonic'}),
      _safeCall('query_key', {'key_type': 'spend_key'}),
      _safeCall('query_key', {'key_type': 'view_key'}),
    ]);
    return WalletSecrets(
      mnemonic: r[0]?['key'] as String? ?? '',
      spendKey: r[1]?['key'] as String? ?? '',
      viewKey: r[2]?['key'] as String? ?? '',
    );
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!await _passwords.verify(oldPassword)) {
      throw WalletException.i18n('notification.errors.invalidOldPassword');
    }
    try {
      await _call('change_wallet_password', {'old_password': oldPassword, 'new_password': newPassword});
    } catch (_) {
      throw WalletException.i18n('notification.errors.changingPassword');
    }
    await _passwords.remember(newPassword);
  }

  Future<void> deleteWallet(String password) async {
    await _requirePassword(password);
    final base = p.join(walletDir, name);
    await closeWallet();
    for (final f in [base, '$base.keys', '$base.address.txt']) {
      try {
        if (await File(f).exists()) await File(f).delete();
      } catch (_) {}
    }
    await listWallets();
  }

  Future<String> exportKeyImages(String password, String directory) async {
    await _requirePassword(password);
    final r = await _call('export_key_images');
    final images = r['signed_key_images'];
    if (images == null || (images is List && images.isEmpty)) {
      throw WalletException.i18n('notification.warnings.noKeyImageExport');
    }
    final file = File(p.join(directory, 'key_image_export'));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(images));
    return file.path;
  }

  Future<void> importKeyImages(String password, String path) async {
    await _requirePassword(password);
    dynamic images;
    try {
      images = jsonDecode(await File(path).readAsString());
    } catch (_) {
      throw WalletException.i18n('notification.errors.keyImages.reading');
    }
    try {
      await _call('import_key_images', {'signed_key_images': images});
    } catch (_) {
      throw WalletException.i18n('notification.errors.keyImages.importing');
    }
  }

  // ======================================================================
  // Addresses
  // ======================================================================

  /// Validates an address with wallet-rpc (cached; `.bdx` names pass through).
  Future<bool> validateAddress(String input) {
    if (input.toLowerCase().endsWith('.bdx')) return Future.value(true);
    if (_validAddresses.contains(input)) return Future.value(true);
    if (input.length < 95 || input.length > 106 || !RegExp(r'^[0-9A-Za-z]+$').hasMatch(input)) {
      return Future.value(false);
    }
    return _addressChecks[input] ??= _safeCall('validate_address', {'address': input}).then((r) {
      _addressChecks.remove(input);
      final valid = r != null && r['valid'] == true && r['nettype'] == netType.name;
      if (valid) _validAddresses.add(input);
      return valid;
    });
  }

  Future<void> saveAddressBookEntry({
    required String address,
    required String name,
    String description = '',
    bool starred = false,
    int? replaceIndex,
  }) async {
    if (replaceIndex != null) {
      await _call('delete_address_book', {'index': replaceIndex});
    }
    await _call('add_address_book', {
      'address': address,
      'description': AddressBookEntry.encodeDescription(name, description, starred),
    });
    await _safeCall('store');
    await refreshAddressBook();
  }

  Future<void> deleteAddressBookEntry(int index) async {
    await _call('delete_address_book', {'index': index});
    await _safeCall('store');
    await refreshAddressBook();
  }

  Future<void> saveTxNote(String txid, String note) async {
    await _call('set_tx_notes', {
      'txids': [txid],
      'notes': [note],
    });
    Transfer update(Transfer tx) => tx.txid == txid ? tx.withNote(note) : tx;
    _confirmed = _confirmed.map(update).toList();
    _transient = _transient.map(update).toList();
    _transferFingerprint = null;
    transfers = _sortedTransfers();
    notifyListeners();
  }

  // ======================================================================
  // Sending
  // ======================================================================

  /// Prepares a transfer (not relayed) so fees can be confirmed.
  /// [password] is checked when given; pass null when the UI is unlocked and
  /// the user hasn't asked for a password on every send.
  Future<PendingTransfer> prepareTransfer({
    required String? password,
    required int amount,
    required String address,
    required int priority,
    bool sweepAll = false,
  }) async {
    if (password != null) await _requirePassword(password);
    final isSweep = sweepAll || amount == unlockedBalance;
    final params = <String, dynamic>{
      if (isSweep) ...{
        'address': address,
        'account_index': 0,
        'subaddr_indices_all': true,
      } else
        'destinations': [
          {'amount': amount, 'address': address},
        ],
      'priority': priority,
      'do_not_relay': true,
      'get_tx_metadata': true,
    };
    final r = await _call(isSweep ? 'sweep_all' : 'transfer_split', params);
    List<int> ints(Object? v) => ((v as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    return PendingTransfer(
      metadata: ((r['tx_metadata_list'] as List?) ?? const []).cast<String>(),
      amounts: ints(r['amount_list']),
      fees: ints(r['fee_list']),
      destination: address,
      priority: priority,
      isSweepAll: isSweep,
    );
  }

  /// Relays a prepared transfer. Irreversible.
  /// Returns the hashes of the relayed transactions.
  Future<List<String>> relay(PendingTransfer pending, {String note = ''}) async {
    final hashes = <String>[];
    for (final hex in pending.metadata) {
      final r = await _call('relay_tx', {'hex': hex, 'flash': pending.isFlash});
      final txHash = r['tx_hash'] as String?;
      if (txHash != null) hashes.add(txHash);
      if (note.isNotEmpty && txHash != null) {
        await _safeCall('set_tx_notes', {
          'txids': [txHash],
          'notes': [note],
        });
      }
    }
    _historyRefreshPending = true;
    unawaited(_heartbeatTick());
    return hashes;
  }

  // ======================================================================
  // Master nodes
  // ======================================================================

  Future<void> stake(String password, int amount, String masterNodeKey) async {
    await _requirePassword(password);
    await _call('stake', {'amount': amount, 'destination': address, 'master_node_key': masterNodeKey});
    unawaited(daemon.refreshMasterNodes());
  }

  Future<void> registerMasterNode(String password, String registrationString) async {
    await _requirePassword(password);
    await _call('register_master_node', {'register_master_node_str': registrationString});
    unawaited(daemon.refreshMasterNodes());
  }

  /// Returns (canUnlock, message).
  Future<(bool, String)> canRequestUnlock(String password, String masterNodeKey) async {
    await _requirePassword(password);
    final r = await _call('can_request_stake_unlock', {'master_node_key': masterNodeKey});
    return (r['can_unlock'] == true, r['msg'] as String? ?? '');
  }

  Future<(bool, String)> requestUnlock(String masterNodeKey) async {
    final r = await _call('request_stake_unlock', {'master_node_key': masterNodeKey});
    if (r['unlocked'] == true) unawaited(daemon.refreshMasterNodes());
    return (r['unlocked'] == true, r['msg'] as String? ?? '');
  }

  /// Our signed key images that appear on the deregistration blacklist.
  Future<List<Map<String, dynamic>>> deregisteredStakes(String password) async {
    await _requirePassword(password);
    final r = await _call('export_key_images');
    final signed = ((r['signed_key_images'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final blacklist = {for (final b in daemon.blacklistedKeyImages) b['key_image']: b};
    return [
      for (final s in signed)
        if (blacklist.containsKey(s['key_image'])) {...s, ...blacklist[s['key_image']]!},
    ];
  }

  // ======================================================================
  // BNS
  // ======================================================================

  static String fullBnsName(String name) {
    final lower = name.trim().toLowerCase();
    return lower.endsWith('.bdx') ? lower : '$lower.bdx';
  }

  Future<void> purchaseBns({
    required String password,
    required String years,
    required String name,
    String owner = '',
    String backupOwner = '',
    String valueWallet = '',
    String valueBchat = '',
    String valueBelnet = '',
    String valueEth = '',
  }) async {
    await _requirePassword(password);
    try {
      await _call('bns_buy_mapping', {
        'years': years,
        'owner': owner.trim().isEmpty ? null : owner.trim(),
        'backup_owner': backupOwner.trim().isEmpty ? null : backupOwner.trim(),
        'name': fullBnsName(name),
        'value_bchat': valueBchat,
        'value_belnet': valueBelnet,
        'value_wallet': valueWallet,
        'value_eth_addr': valueEth,
      });
    } on WalletException catch (e) {
      final msg = e.message ?? '';
      if (msg.contains('already registered')) {
        throw WalletException.message('Cannot buy a BNS name that is already registered');
      }
      if (msg.contains('Transaction is too big')) {
        throw WalletException.message('Transaction is too big, please do the sweep_all from [masternode -> stakings]');
      }
      rethrow;
    }
    Timer(const Duration(seconds: 5), refreshBnsRecords);
  }

  Future<void> renewBns(String password, String name, String years) async {
    await _requirePassword(password);
    await _call('bns_renew_mapping', {'years': years, 'name': fullBnsName(name)});
    Timer(const Duration(seconds: 5), refreshBnsRecords);
  }

  Future<void> updateBns({
    required String password,
    required String name,
    String? owner,
    String? backupOwner,
    String? valueWallet,
    String? valueBchat,
    String? valueBelnet,
    String? valueEth,
  }) async {
    await _requirePassword(password);
    final params = <String, dynamic>{
      'name': fullBnsName(name),
      if (owner?.isNotEmpty ?? false) 'owner': owner,
      if (backupOwner?.isNotEmpty ?? false) 'backup_owner': backupOwner,
      if (valueWallet?.isNotEmpty ?? false) 'value_wallet': valueWallet,
      if (valueBchat?.isNotEmpty ?? false) 'value_bchat': valueBchat,
      if (valueBelnet?.isNotEmpty ?? false) 'value_belnet': valueBelnet,
      if (valueEth?.isNotEmpty ?? false) 'value_eth_addr': valueEth,
    };
    await _call('bns_update_mapping', params);
    bnsRecords = [
      for (final r in bnsRecords)
        if (r.name?.toLowerCase() == params['name']) BnsRecord({...r.raw, ...params}) else r,
    ];
    notifyListeners();
    Timer(const Duration(seconds: 5), refreshBnsRecords);
  }

  /// Decrypts (and caches in the wallet) one of our records by name.
  Future<bool> decryptBnsRecord(String name) async {
    final full = fullBnsName(name);
    final hash = await _safeCall('bns_hash_name', {'name': full});
    final nameHash = hash?['name'] as String?;
    if (nameHash == null) return false;
    final record = await daemon.bnsRecord(nameHash);
    if (record == null || !bnsRecords.any((r) => r.nameHash == nameHash)) return false;
    await _safeCall('bns_add_known_names', {
      'names': [
        {'name': full},
      ],
    });
    await refreshBnsRecords();
    return true;
  }

  Future<void> refreshBnsRecords() async {
    if (!isOpen) return;
    try {
      final addrData = await _call('get_address', {'account_index': 0}, const Duration(seconds: 5));
      final owners = (addrData['addresses'] as List? ?? const [])
          .map((a) => (a as Map)['address'] as String?)
          .whereType<String>()
          .toList();
      final records = await daemon.bnsRecordsForOwners(owners);
      final known = await _safeCall('bns_known_names', {'decrypt': true, 'include_expired': false});
      final knownByHash = {
        for (final k in (known?['known_names'] as List? ?? const [])) (k as Map)['hashed']: k.cast<String, dynamic>(),
      };
      final merged =
          [
            for (final r in records)
              BnsRecord({
                ...r,
                if (knownByHash[r['name_hash']] case final k?) ...{
                  'name': k['name'],
                  'expiration_height': k['expiration_height'],
                  'value_wallet': k['value_wallet'] ?? '',
                  'value_bchat': k['value_bchat'] ?? '',
                  'value_belnet': k['value_belnet'] ?? '',
                  'value_eth_addr': k['value_eth_addr'] ?? '',
                },
              }),
          ]..sort((a, b) {
            if (!a.isLocked && b.isLocked) return -1;
            if (a.isLocked && !b.isLocked) return 1;
            if (!a.isLocked && !b.isLocked) return a.name!.compareTo(b.name!);
            return b.updateHeight - a.updateHeight;
          });
      bnsRecords = merged;
      notifyListeners();
    } catch (e) {
      debugPrint('BNS refresh failed: $e');
    }
  }

  // ======================================================================
  // Proofs & signatures
  // ======================================================================

  Future<Map<String, dynamic>> proveTransaction(String txid, String address, String message) {
    final hasAddress = address.trim().isNotEmpty;
    return _call(hasAddress ? 'get_tx_proof' : 'get_spend_proof', {
      'txid': txid.trim(),
      if (hasAddress) 'address': address.trim(),
      if (message.trim().isNotEmpty) 'message': message.trim(),
    });
  }

  Future<Map<String, dynamic>> checkTransaction(String txid, String signature, String address, String message) {
    final hasAddress = address.trim().isNotEmpty;
    return _call(hasAddress ? 'check_tx_proof' : 'check_spend_proof', {
      'txid': txid.trim(),
      'signature': signature.trim(),
      if (hasAddress) 'address': address.trim(),
      if (message.trim().isNotEmpty) 'message': message.trim(),
    });
  }

  Future<String> sign(String data) async => (await _call('sign', {'data': data}))['signature'] as String;

  Future<bool> verify(String data, String address, String signature) async {
    final r = await _call('verify', {'data': data, 'address': address, 'signature': signature});
    return r['good'] == true;
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _bnsHeartbeat?.cancel();
    super.dispose();
  }
}
