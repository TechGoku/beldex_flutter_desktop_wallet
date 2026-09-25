import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import '../services/binaries.dart';
import '../services/daemon_service.dart';
import '../services/wallet_service.dart';

enum StartupStage { loadingConfig, needsSetup, startingDaemon, startingWallet, readingWallets, ready, failed, quitting }

/// One-off messages for the UI to show as snackbars.
class AppNotice {
  AppNotice(this.message, {this.error = false, this.warning = false});
  final String message;
  final bool error;
  final bool warning;
}

/// Owns configuration and the lifecycle of the daemon and wallet services.
class AppController extends ChangeNotifier {
  AppController() {
    wallet = WalletService(daemon);
    wallet.onUnexpectedExit = _recoverWallet;
    daemon.onUnexpectedExit = _restartLocalNode;
    daemon.onUnreachable = _failover;
    // A closed wallet can't be locked; the next one opens unlocked
    wallet.addListener(() {
      if (!wallet.isOpen && locked) {
        locked = false;
        _idleTimer?.cancel();
        notifyListeners();
      }
    });
  }

  final DaemonService daemon = DaemonService();
  late final WalletService wallet;

  AppConfig config = AppConfig.defaults();
  StartupStage stage = StartupStage.loadingConfig;
  String? failure;
  String? daemonVersion;
  bool usingFallbackRemote = false;

  final _notices = StreamController<AppNotice>.broadcast();
  Stream<AppNotice> get notices => _notices.stream;
  void notify(String message, {bool error = false, bool warning = false}) =>
      _notices.add(AppNotice(message, error: error, warning: warning));

  bool get isDark => config.darkTheme;

  // ---- UI lock (the wallet stays open and keeps syncing while locked) ----
  bool locked = false;
  Timer? _idleTimer;

  /// Call on any user input; restarts the auto-lock countdown.
  void userActivity() {
    _idleTimer?.cancel();
    final minutes = config.autoLockMinutes;
    if (minutes <= 0 || !wallet.isOpen || locked) return;
    _idleTimer = Timer(Duration(minutes: minutes), lock);
  }

  void lock() {
    if (!wallet.isOpen) return;
    _idleTimer?.cancel();
    locked = true;
    notifyListeners();
  }

  Future<bool> unlock(String password) async {
    if (!await wallet.verifyPassword(password)) return false;
    locked = false;
    notifyListeners();
    userActivity();
    return true;
  }

  /// Remembers the wallet to preselect on the unlock screen.
  Future<void> rememberWallet(String name) async {
    if (config.lastWallet == name) return;
    config.lastWallet = name;
    await config.save();
  }

  Future<void> updatePreferences(void Function(AppConfig c) change) async {
    change(config);
    await config.save();
    notifyListeners();
    userActivity();
  }

  Future<void> boot() async {
    final loaded = await AppConfig.load();
    if (loaded != null) config = loaded;
    await I18n.instance.load(config.language);
    if (loaded == null) {
      _setStage(StartupStage.needsSetup);
      return;
    }
    await _startServices();
  }

  /// Called from the welcome/settings screens.
  Future<void> saveConfigAndStart(AppConfig newConfig) async {
    config = newConfig;
    await config.save();
    await _startServices();
  }

  Future<void> setLanguage(String code) async {
    config.language = code;
    await I18n.instance.load(code);
    if (stage != StartupStage.needsSetup) await config.save();
    notifyListeners();
  }

  Future<void> setDarkTheme(bool dark) async {
    config.darkTheme = dark;
    await config.save();
    notifyListeners();
  }

  /// Saves settings. A different node on the same network is switched to
  /// live: the open wallet stays open and keeps syncing from the same block.
  /// Throws if that node doesn't answer (nothing changes then). Returns true
  /// when a restart is still needed (network or data folders changed).
  Future<bool> saveSettings(AppConfig newConfig) async {
    if (!_sameConnection(config, newConfig) && _onlyNodeChanged(config, newConfig)) {
      await switchNode(newConfig);
      return false;
    }
    final restart = !_sameConnection(config, newConfig);
    config = newConfig;
    await config.save();
    notifyListeners();
    return restart;
  }

  /// Switches to [next]'s node without restarting anything.
  Future<void> switchNode(AppConfig next) async {
    await daemon.switchTo(next);
    final d = next.daemon;
    if (d.type == DaemonType.remote) {
      wallet.setNode(d.remoteHost, d.remotePort);
    } else {
      wallet.setNode(d.rpcBindIp, d.rpcBindPort);
    }
    config = next;
    await config.save();
    notifyListeners();
  }

  static bool _onlyNodeChanged(AppConfig a, AppConfig b) {
    if (a.netType != b.netType) return false;
    final net = a.netType.name;
    Map<String, Object?> rest(AppConfig c) =>
        Map.of(_flatten(c.toJson()))
          ..removeWhere((k, _) => k == 'language' || k == 'dark_theme' || k.startsWith('daemons.$net.'));
    return mapEquals(rest(a), rest(b));
  }

  // ---- recovery ------------------------------------------------------------

  bool _failingOver = false;

  /// The remote node stopped answering: move to a working public node.
  Future<void> _failover() async {
    final d = config.daemon;
    if (_failingOver || d.type != DaemonType.remote || stage != StartupStage.ready) return;
    _failingOver = true;
    try {
      final next = await daemon.findWorkingRemote(config.netType, exclude: d.remoteHost);
      if (next == null) {
        notify('${d.remoteHost} is not answering and no other node is reachable; still trying', warning: true);
        return;
      }
      final c = config.copy();
      c.daemon
        ..remoteHost = next.host
        ..remotePort = next.port;
      final previous = d.remoteHost;
      await switchNode(c);
      notify('$previous stopped answering; switched to ${next.host}', warning: true);
    } catch (_) {
      // Keep the current node; the next failed check tries again
    } finally {
      _failingOver = false;
    }
  }

  /// wallet-rpc exited unexpectedly: restart it and go back to unlock.
  Future<void> _recoverWallet(int exitCode) async {
    if (stage != StartupStage.ready) return;
    final wasOpen = wallet.isOpen;
    try {
      await wallet.recoverFromCrash();
      if (wasOpen) {
        notify('The wallet service stopped unexpectedly and was restarted. Unlock your wallet again.', error: true);
      }
    } catch (e) {
      failure = 'The wallet service stopped and could not be restarted: $e';
      _setStage(StartupStage.failed);
    }
  }

  /// A local beldexd exited unexpectedly: start it again.
  Future<void> _restartLocalNode(int exitCode) async {
    if (stage != StartupStage.ready) return;
    notify('The local node stopped unexpectedly and is restarting', warning: true);
    try {
      await daemon.start(config);
    } catch (e) {
      notify('Could not restart the local node: $e', error: true);
    }
  }

  static bool _sameConnection(AppConfig a, AppConfig b) {
    final ja = a.toJson()
      ..remove('language')
      ..remove('dark_theme');
    final jb = b.toJson()
      ..remove('language')
      ..remove('dark_theme');
    return mapEquals(_flatten(ja), _flatten(jb));
  }

  static Map<String, Object?> _flatten(Map<String, dynamic> m, [String prefix = '']) => {
    for (final e in m.entries)
      if (e.value is Map)
        ..._flatten((e.value as Map).cast<String, dynamic>(), '$prefix${e.key}.')
      else
        '$prefix${e.key}': e.value,
  };

  Future<void> _startServices() async {
    failure = null;
    try {
      _setStage(StartupStage.startingDaemon);
      final d = config.daemon;

      if (d.type != DaemonType.local) {
        // Make sure the remote node answers; fail over to a public node if not
        try {
          final r = await daemon.checkRemote(d.remoteHost, d.remotePort, timeout: const Duration(seconds: 10));
          if (r.nettype.isNotEmpty && r.nettype != config.netType.name) {
            throw StateError(t('notification.errors.differentNetType'));
          }
        } on StateError {
          rethrow;
        } catch (_) {
          if (d.type == DaemonType.localRemote) {
            d.type = DaemonType.local;
            notify(t('notification.warnings.usingLocalNode'), warning: true);
          } else {
            final fallback = await daemon.findWorkingRemote(config.netType, exclude: d.remoteHost);
            if (fallback == null) throw StateError(t('notification.errors.cannotAccessRemoteNode'));
            d.remoteHost = fallback.host;
            d.remotePort = fallback.port;
            usingFallbackRemote = true;
            await config.save();
            notify('Remote node unreachable, switched to $fallback', warning: true);
          }
        }
      }

      if (d.runsLocally) {
        daemonVersion = await Binaries.daemonVersion();
        if (daemonVersion == null) {
          // Binary missing (e.g. removed by an anti-virus): use a remote node
          d.type = DaemonType.remote;
          if (d.remoteHost.isEmpty) {
            final fallback = await daemon.findWorkingRemote(config.netType);
            if (fallback == null) throw StateError(t('notification.errors.cannotAccessRemoteNode'));
            d.remoteHost = fallback.host;
            d.remotePort = fallback.port;
          }
          notify(t('notification.warnings.usingRemoteNode'), warning: true);
        }
      }

      try {
        await daemon.start(config);
      } catch (e) {
        throw StateError(d.type == DaemonType.remote ? t('notification.errors.remoteCannotBeReached') : '$e');
      }

      _setStage(StartupStage.startingWallet);
      await wallet.start(config);

      _setStage(StartupStage.readingWallets);
      await wallet.listWallets(includeLegacy: true);
      _setStage(StartupStage.ready);
    } catch (e) {
      failure = e is StateError ? e.message : '$e';
      await daemon.stop();
      _setStage(StartupStage.failed);
    }
  }

  void _setStage(StartupStage s) {
    stage = s;
    notifyListeners();
  }

  Future<void> shutdown() async {
    _setStage(StartupStage.quitting);
    await wallet.stop();
    await daemon.stop();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _notices.close();
    super.dispose();
  }
}
