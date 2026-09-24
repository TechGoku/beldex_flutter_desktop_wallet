import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../services/daemon_service.dart';
import '../../../services/models.dart';
import '../../../services/price_service.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../explorer.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText, runWithProgress;
import '../onboarding/add_wallet.dart';
import '../wallet/advanced_page.dart';
import '../wallet/bns_page.dart';
import '../wallet/master_nodes_page.dart';
import '../wallet/swap_page.dart';
import 'contacts_view.dart';
import 'receive_view.dart';
import 'send_view.dart';
import 'wallet_settings_view.dart';

enum HomeView { home, transactions, send, receive, contacts, swap, stake, bns, tools, settings }

/// Node the app is talking to, for status lines.
String nodeLabel(DaemonConfig d) => switch (d.type) {
  DaemonType.remote => d.remoteHost,
  DaemonType.local => 'Local node',
  DaemonType.localRemote => 'Local node + ${d.remoteHost}',
};

/// Desktop shell: navigation sidebar on the left, the selected page on the right.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static _HomeScreenState? of(BuildContext context) => context.findAncestorStateOfType<_HomeScreenState>();

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeView _view = HomeView.home;
  String? _sendTo;
  int _stakeTab = 0;

  HomeView get view => _view;

  void show(HomeView view) => setState(() {
    _view = view;
    _stakeTab = 0;
    if (view != HomeView.send) _sendTo = null;
  });

  void sendTo(String address) => setState(() {
    _sendTo = address;
    _view = HomeView.send;
  });

  /// Master nodes page opened on its registration tab.
  void registerMasterNode() => setState(() {
    _view = HomeView.stake;
    _stakeTab = 1;
  });

  void back() => show(HomeView.home);

  @override
  void initState() {
    super.initState();
    context.read<PriceService>().refresh();
  }

  static const _numbered = [
    HomeView.home,
    HomeView.transactions,
    HomeView.send,
    HomeView.receive,
    HomeView.contacts,
    HomeView.swap,
    HomeView.stake,
    HomeView.bns,
    HomeView.tools,
  ];
  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final wallet = context.read<WalletService>();
    return CallbackShortcuts(
      bindings: {
        for (final (i, v) in _numbered.indexed) SingleActivator(_digits[i], control: true): () => show(v),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => show(HomeView.settings),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): app.lock,
        const SingleActivator(LogicalKeyboardKey.f5): wallet.refreshAll,
      },
      child: Focus(
        autofocus: true,
        child: BScaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(view: _view, onSelect: show),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: KeyedSubtree(key: ValueKey(_view), child: _body()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_view) {
    HomeView.home => const _Page(title: 'Overview', child: _Overview()),
    HomeView.transactions => const _Page(title: 'Transactions', child: _Transactions()),
    HomeView.send => _Page(
      title: 'Send BDX',
      subtitle: 'Pay an address, subaddress or BNS name',
      child: SendView(initialAddress: _sendTo, onDone: back),
    ),
    HomeView.receive => const _Page(
      title: 'Receive BDX',
      subtitle: 'Share your address, or give each payer their own subaddress',
      child: ReceiveView(),
    ),
    HomeView.contacts => const _Page(title: 'Contacts', subtitle: 'Saved addresses', child: ContactsView()),
    HomeView.settings => const _Page(title: 'Settings', child: WalletSettingsView()),
    HomeView.swap => const _Page(
      title: 'Swap',
      subtitle: 'Exchange BDX with other coins',
      scroll: false,
      child: SwapPage(),
    ),
    HomeView.stake => _Page(
      title: 'Master nodes',
      subtitle: 'Stake, register and unlock',
      scroll: false,
      child: MasterNodesPage(key: ValueKey(_stakeTab), initialTab: _stakeTab),
    ),
    HomeView.bns => const _Page(
      title: 'BNS names',
      subtitle: 'Beldex Name Service: human-readable .bdx names',
      scroll: false,
      child: BnsPage(),
    ),
    HomeView.tools => const _Page(
      title: 'Tools',
      subtitle: 'Payment proofs, message signing and key images',
      scroll: false,
      child: AdvancedPage(),
    ),
  };
}

/// Page frame: title row plus a centered content area capped at [maxWidth].
class _Page extends StatelessWidget {
  const _Page({required this.title, this.subtitle, required this.child, this.scroll = true});
  final String title;
  final String? subtitle;
  final Widget child;
  final bool scroll;

  static const maxWidth = 1180.0;

  Widget _capped(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 26, 32, 20),
        child: _capped(PageHeader(title: title, subtitle: subtitle)),
      ),
      Expanded(
        child: scroll
            ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(32, 0, 32, 32), child: _capped(child))
            : Padding(padding: const EdgeInsets.fromLTRB(32, 0, 32, 0), child: _capped(child)),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.view, required this.onSelect});
  final HomeView view;
  final ValueChanged<HomeView> onSelect;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final viewOnly = context.select<WalletService, bool>((w) => w.viewOnly);

    Widget item(HomeView v, IconData icon, String label, {String? keys}) =>
        _NavItem(icon: icon, label: label, active: view == v, shortcut: keys, onTap: () => onSelect(v));

    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0C),
        border: Border(right: BorderSide(color: BeldexColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 14, 18),
            child: Row(
              children: [
                SvgPicture.asset('assets/images/logo.svg', width: 26, height: 26),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text(
                    'BELDEX',
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(fontFamily: BeldexFonts.display, fontSize: 13, letterSpacing: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const _WalletSwitcher(),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                const _NavGroup('Wallet'),
                item(HomeView.home, Icons.space_dashboard_outlined, 'Overview', keys: 'Ctrl+1'),
                item(HomeView.transactions, Icons.receipt_long_outlined, 'Transactions', keys: 'Ctrl+2'),
                if (!viewOnly) item(HomeView.send, Icons.arrow_upward, 'Send', keys: 'Ctrl+3'),
                item(HomeView.receive, Icons.arrow_downward, 'Receive', keys: 'Ctrl+4'),
                item(HomeView.contacts, Icons.contacts_outlined, 'Contacts', keys: 'Ctrl+5'),
                const _NavGroup('Services'),
                item(HomeView.swap, Icons.swap_horiz, 'Swap', keys: 'Ctrl+6'),
                item(HomeView.stake, Icons.dns_outlined, 'Master nodes', keys: 'Ctrl+7'),
                item(HomeView.bns, Icons.alternate_email, 'BNS names', keys: 'Ctrl+8'),
                item(HomeView.tools, Icons.construction_outlined, 'Tools', keys: 'Ctrl+9'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                item(HomeView.settings, Icons.settings_outlined, 'Settings', keys: 'Ctrl+,'),
                _NavItem(icon: Icons.lock_outline, label: 'Lock', shortcut: 'Ctrl+L', onTap: app.lock),
              ],
            ),
          ),
          const _SyncStatus(),
        ],
      ),
    );
  }
}

class _NavGroup extends StatelessWidget {
  const _NavGroup(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontFamily: BeldexFonts.display,
        fontSize: 9.5,
        color: BeldexColors.faint,
        letterSpacing: 1.5,
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.onTap, this.active = false, this.shortcut});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final row = Material(
      color: active ? const Color(0xFF171717) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: BeldexColors.hover,
        child: Container(
          height: 38,
          padding: const EdgeInsets.only(left: 12, right: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: active ? BeldexColors.green : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? BeldexColors.green : BeldexColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: active ? BeldexColors.text : const Color(0xFFBDBDBD),
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: shortcut == null
          ? row
          : Tooltip(message: shortcut!, waitDuration: const Duration(milliseconds: 700), child: row),
    );
  }
}

/// Current wallet; opens the wallet list.
class _WalletSwitcher extends StatelessWidget {
  const _WalletSwitcher();

  @override
  Widget build(BuildContext context) {
    final name = context.select<WalletService, String>((w) => w.name);
    final address = context.select<WalletService, String>((w) => w.address);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Tooltip(
        message: 'Switch wallet',
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: BeldexColors.panel,
          shape: const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
          child: InkWell(
            onTap: () => _showWallets(context),
            hoverColor: BeldexColors.hover,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Wallet' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: BeldexFonts.display,
                            fontSize: 13,
                            color: BeldexColors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shorten(address, head: 7, tail: 6),
                          style: const TextStyle(fontSize: 11.5, color: BeldexColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.unfold_more, size: 18, color: BeldexColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showWallets(BuildContext context) async {
    final wallet = context.read<WalletService>();
    final app = context.read<AppController>();
    await wallet.listWallets();
    if (!context.mounted) return;
    await showBModal<void>(
      context,
      width: 440,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Wallets'),
            for (final w in wallet.walletList.wallets)
              MenuRow(
                icon: w.name == wallet.name ? Icons.check : Icons.account_balance_wallet_outlined,
                label: w.name,
                subtitle: w.address == null ? null : shorten(w.address!, head: 8, tail: 8),
                trailing: w.name == wallet.name ? const SizedBox.shrink() : null,
                onTap: w.name == wallet.name
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        // Switching closes this wallet; the unlock screen asks for the other one's password
                        await runWithProgress(context, () => wallet.closeWallet());
                        await app.rememberWallet(w.name);
                      },
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: GhostButton('Close', onPressed: () => Navigator.pop(ctx))),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    '+ Add wallet',
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await runWithProgress(context, () => wallet.closeWallet());
                      if (context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddWalletScreen()));
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
  }
}

/// Sync state and node, pinned to the bottom of the sidebar.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    final height = context.select<WalletService, int>((w) => w.height);
    final target = context.select<DaemonService, int>((d) => d.info.height);
    final config = context.read<AppController>().config;
    final node = nodeLabel(config.daemon);
    final net = config.netType;
    final sync = syncState(height, target);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BeldexColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: IconLabel(sync.icon, sync.label, color: sync.color, size: 12)),
              NetLabel(net.name, warn: net != NetType.mainnet),
            ],
          ),
          if (!sync.synced && target > 0) ...[const SizedBox(height: 8), GlowProgress(sync.progress)],
          const SizedBox(height: 6),
          Text(
            target == 0 ? node : 'Block ${groupDigits(target)} · $node',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: BeldexColors.muted),
          ),
        ],
      ),
    );
  }
}

typedef SyncState = ({bool synced, double progress, String label, Color color, IconData icon});

SyncState syncState(int walletHeight, int nodeHeight) {
  if (nodeHeight == 0) {
    return (synced: false, progress: 0, label: 'Connecting…', color: BeldexColors.amber, icon: Icons.sync);
  }
  // The wallet normally trails the node by a block or two between polls
  final synced = walletHeight >= nodeHeight - 3;
  final progress = (walletHeight / nodeHeight).clamp(0.0, 1.0);
  return synced
      ? (synced: true, progress: 1, label: 'Synced', color: BeldexColors.green, icon: Icons.circle)
      : (
          synced: false,
          progress: progress,
          label: 'Scanning ${(progress * 100).toStringAsFixed(1)}%',
          color: BeldexColors.amber,
          icon: Icons.sync,
        );
}

// ---------------------------------------------------------------------------
// Overview

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ResponsiveRow(flex: [3, 2], breakpoint: 820, stretch: true, children: [_BalancePanel(), _AddressPanel()]),
      SizedBox(height: 16),
      ResponsiveRow(flex: [3, 2], breakpoint: 820, children: [_RecentPanel(), _NetworkPanel()]),
    ],
  );
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel();

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    final app = context.watch<AppController>();
    final price = context.select<PriceService, double?>((p) => p.usd);
    final hidden = app.config.hideBalance;
    String mask(String s) => hidden ? '••••••' : s;
    final locked = (w.balance - w.unlockedBalance).clamp(0, 1 << 62);
    final home = HomeScreen.of(context)!;

    Widget stat(String label, String value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: BeldexColors.muted)),
        const SizedBox(height: 4),
        Text(
          '${mask(value)} BDX',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );

    return Panel(
      title: 'Total balance',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: hidden ? 'Show balance' : 'Hide balance',
            iconSize: 17,
            color: BeldexColors.muted,
            visualDensity: VisualDensity.compact,
            onPressed: () => app.updatePreferences((c) => c.hideBalance = !c.hideBalance),
            icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: 'Refresh (F5)',
            iconSize: 17,
            color: BeldexColors.green,
            visualDensity: VisualDensity.compact,
            onPressed: w.balanceLoading ? null : w.refreshAll,
            icon: w.balanceLoading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mask(formatBdx(w.balance)),
                    style: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 36, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text('BDX', style: TextStyle(fontSize: 15, color: BeldexColors.green)),
            ],
          ),
          const SizedBox(height: 6),
          if (app.config.showFiat && price != null)
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted),
                children: [
                  const TextSpan(text: '≈ '),
                  TextSpan(
                    text: mask('${(w.balance / atomicUnitsPerBdx * price).toStringAsFixed(2)} USD'),
                    style: const TextStyle(color: BeldexColors.text, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '   1 BDX = ${price.toStringAsFixed(4)} USD'),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 36,
            runSpacing: 10,
            children: [
              stat('Unlocked', formatBdx(w.unlockedBalance), BeldexColors.green),
              stat('Locked', formatBdx(locked), BeldexColors.amber),
            ],
          ),
          if (w.viewOnly) ...[const SizedBox(height: 10), const Muted('View-only wallet: it cannot spend.')],
          const SizedBox(height: 22),
          Row(
            children: [
              if (!w.viewOnly) ...[
                SizedBox(
                  width: 150,
                  child: PrimaryButton('Send', icon: Icons.arrow_upward, onPressed: () => home.show(HomeView.send)),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 150,
                child: PrimaryButton(
                  'Receive',
                  icon: Icons.arrow_downward,
                  onPressed: () => home.show(HomeView.receive),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel();

  @override
  Widget build(BuildContext context) {
    final address = context.select<WalletService, String>((w) => w.address);
    return Panel(
      title: 'Primary address',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 132,
            height: 132,
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: address.isEmpty ? ' ' : address,
              size: 116,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(address, style: const TextStyle(fontSize: 12, color: BeldexColors.muted, height: 1.5)),
                const SizedBox(height: 12),
                CopyButton(address),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel();

  @override
  Widget build(BuildContext context) {
    final transfers = context.select<WalletService, List<Transfer>>((w) => w.transfers);
    final loaded = context.select<WalletService, bool>((w) => w.historyLoaded);
    final recent = transfers.take(8).toList();
    return Panel(
      title: 'Recent activity',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      trailing: TextLink('View all →', onTap: () => HomeScreen.of(context)!.show(HomeView.transactions)),
      child: !loaded && transfers.isEmpty
          ? Column(children: [for (var i = 0; i < 4; i++) const _SkeletonRow()])
          : recent.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Muted('No transactions yet', center: true),
            )
          : Column(
              children: [for (final (i, tx) in recent.indexed) _TxRow(tx: tx, last: i == recent.length - 1)],
            ),
    );
  }
}

class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    final height = context.select<WalletService, int>((w) => w.height);
    final info = context.select<DaemonService, DaemonInfo>((d) => d.info);
    final sync = syncState(height, info.height);
    final net = app.config.netType;
    return Panel(
      title: 'Network',
      trailing: NetLabel(net.name, warn: net != NetType.mainnet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconLabel(sync.icon, sync.label, color: sync.color, size: 13),
          const SizedBox(height: 10),
          GlowProgress(info.height == 0 ? 0 : sync.progress),
          const SizedBox(height: 8),
          DetailLine.text('Wallet height', height == 0 ? '…' : groupDigits(height)),
          DetailLine.text('Node height', info.height == 0 ? '…' : groupDigits(info.height)),
          DetailLine.text('Node', nodeLabel(app.config.daemon), last: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transactions

enum _Filter { all, received, sent, pending }

class _Transactions extends StatefulWidget {
  const _Transactions();
  @override
  State<_Transactions> createState() => _TransactionsState();
}

class _TransactionsState extends State<_Transactions> {
  _Filter _filter = _Filter.all;
  String _query = '';
  int _limit = 50;
  List<Transfer>? _source;
  String? _key;
  List<Transfer> _filtered = const [];
  final _search = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Transfer> _apply(List<Transfer> all, List<AddressBookEntry> book) {
    final key = '$_filter|$_query';
    if (identical(all, _source) && key == _key) return _filtered;
    _source = all;
    _key = key;
    final q = _query.toLowerCase();
    final names = {for (final e in book) e.address: e.name.toLowerCase()};
    _filtered = all
        .where((tx) {
          final ok = switch (_filter) {
            _Filter.all => true,
            _Filter.received => tx.isIncoming && !tx.isPending,
            _Filter.sent => tx.isOutgoing && tx.type != 'pending',
            _Filter.pending => tx.isPending,
          };
          if (!ok) return false;
          if (q.isEmpty) return true;
          final addresses = [tx.address, ...tx.destinations.map((d) => '${d['address']}')];
          return tx.txid.contains(q) ||
              tx.note.toLowerCase().contains(q) ||
              formatBdx(tx.amount).contains(q) ||
              addresses.any((a) => a.toLowerCase().contains(q) || (names[a]?.contains(q) ?? false));
        })
        .toList(growable: false);
    return _filtered;
  }

  @override
  Widget build(BuildContext context) {
    final transfers = context.select<WalletService, List<Transfer>>((w) => w.transfers);
    final loaded = context.select<WalletService, bool>((w) => w.historyLoaded);
    final book = context.select<WalletService, List<AddressBookEntry>>((w) => w.addressBook);
    final list = _apply(transfers, book);
    final shown = list.take(_limit).toList();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyF, control: true): _search.requestFocus},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilterChips<_Filter>(
                options: const {
                  _Filter.all: 'All',
                  _Filter.received: '↓ Received',
                  _Filter.sent: '↑ Sent',
                  _Filter.pending: 'Pending',
                },
                value: _filter,
                onChanged: (f) => setState(() {
                  _filter = f;
                  _limit = 50;
                }),
              ),
              const SizedBox(width: 14),
              Muted('${list.length} of ${transfers.length}', size: 12),
              const Spacer(),
              SizedBox(
                width: 340,
                child: TextField(
                  focusNode: _search,
                  onChanged: (v) => setState(() {
                    _query = v.trim();
                    _limit = 50;
                  }),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search tx id, note, amount, contact (Ctrl+F)',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: BeldexColors.panel,
            shape: const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 860;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: BeldexColors.border)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(flex: 3, child: TableHead('Type')),
                          const Expanded(flex: 3, child: TableHead('Date')),
                          if (wide) const Expanded(flex: 4, child: TableHead('Details')),
                          const Expanded(flex: 3, child: TableHead('Amount', align: TextAlign.right)),
                          const SizedBox(width: 120, child: TableHead('Status', align: TextAlign.right)),
                        ],
                      ),
                    ),
                    if (!loaded && transfers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(children: [for (var i = 0; i < 6; i++) const _SkeletonRow()]),
                      )
                    else if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Muted(transfers.isEmpty ? 'No transactions yet' : 'Nothing matches', center: true),
                      )
                    else
                      for (final tx in shown) _TxTableRow(tx: tx, wide: wide),
                  ],
                );
              },
            ),
          ),
          if (list.length > _limit) ...[
            const SizedBox(height: 12),
            Center(
              child: GhostButton(
                'Show more (${list.length - _limit} older)',
                expand: false,
                onPressed: () => setState(() => _limit += 50),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TxTableRow extends StatelessWidget {
  const _TxTableRow({required this.tx, required this.wide});
  final Transfer tx;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final s = txStyle(tx);
    final hidden = context.select<AppController, bool>((a) => a.config.hideBalance);
    final daemonHeight = context.select<DaemonService, int>((d) => d.info.height);
    final confirmations = tx.isPending
        ? 0
        : (tx.confirmations > 0 ? tx.confirmations : (daemonHeight - tx.height + 1).clamp(0, 1 << 30));
    final status = tx.type == 'failed'
        ? const IconLabel(Icons.close, 'Failed', color: BeldexColors.red, size: 12)
        : tx.isPending
        ? const IconLabel(Icons.schedule, 'Pending', color: BeldexColors.amber, size: 12)
        : confirmations < 10
        ? IconLabel(Icons.hourglass_bottom, '$confirmations/10', color: BeldexColors.amber, size: 12)
        : const IconLabel(Icons.check, 'Confirmed', color: BeldexColors.muted, size: 12);
    return InkWell(
      onTap: () => showTxDetails(context, tx),
      hoverColor: BeldexColors.hover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: BeldexColors.rowBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(border: Border.all(color: s.color)),
                    child: Icon(s.icon, size: 14, color: s.color),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      txLabel(tx),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                tx.timestamp > 0 ? formatTimestamp(tx.timestamp) : '—',
                style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted),
              ),
            ),
            if (wide)
              Expanded(
                flex: 4,
                child: Text(
                  tx.note.isNotEmpty ? tx.note : shorten(tx.txid, head: 12, tail: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: tx.note.isNotEmpty ? BeldexColors.text : BeldexColors.muted),
                ),
              ),
            Expanded(
              flex: 3,
              child: Text(
                '${s.sign}${hidden ? '••••' : formatBdx(tx.amount)} BDX',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: s.color),
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(alignment: Alignment.centerRight, child: status),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Skeleton(width: 28, height: 28),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Skeleton(width: 220, height: 9), SizedBox(height: 6), Skeleton(width: 70, height: 8)],
          ),
        ),
        Skeleton(width: 60, height: 12),
      ],
    ),
  );
}

({IconData icon, Color color, String sign}) txStyle(Transfer tx) {
  if (tx.type == 'failed') return (icon: Icons.close, color: BeldexColors.red, sign: '');
  if (tx.isPending && tx.isIncoming) return (icon: Icons.south_west, color: BeldexColors.amber, sign: '+');
  if (tx.isPending) return (icon: Icons.north_east, color: BeldexColors.amber, sign: '−');
  return switch (tx.type) {
    'stake' => (icon: Icons.lock_outline, color: BeldexColors.blue, sign: '−'),
    'mnode' || 'miner' || 'gov' => (icon: Icons.stars_outlined, color: BeldexColors.green, sign: '+'),
    'bns' => (icon: Icons.alternate_email, color: BeldexColors.blue, sign: '−'),
    _ =>
      tx.isIncoming
          ? (icon: Icons.south_west, color: BeldexColors.green, sign: '+')
          : (icon: Icons.north_east, color: BeldexColors.red, sign: '−'),
  };
}

String txLabel(Transfer tx) => switch (tx.type) {
  'in' => 'Received',
  'out' => 'Sent',
  'pending' => 'Sending',
  'pool' => 'Incoming (pool)',
  'failed' => 'Failed',
  'miner' => 'Mining reward',
  'mnode' => 'Master node reward',
  'gov' => 'Governance',
  'stake' => 'Stake',
  'bns' => 'BNS purchase',
  _ => tx.type,
};

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx, required this.last});
  final Transfer tx;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = txStyle(tx);
    final hidden = context.select<AppController, bool>((a) => a.config.hideBalance);
    return InkWell(
      onTap: () => showTxDetails(context, tx),
      hoverColor: BeldexColors.hover,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: BeldexColors.rowBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(border: Border.all(color: s.color)),
              child: Icon(s.icon, size: 16, color: s.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.note.isNotEmpty ? tx.note : txLabel(tx),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  if (tx.isPending)
                    tx.type == 'failed'
                        ? const IconLabel(Icons.close, 'failed', color: BeldexColors.red, size: 11.5)
                        : const IconLabel(Icons.schedule, 'pending', color: BeldexColors.amber, size: 11.5)
                  else
                    Text(
                      '${timeAgo(tx.timestamp)} · ${shorten(tx.txid, head: 10, tail: 8)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: BeldexColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${s.sign}${hidden ? '••••' : formatBdx(tx.amount)}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: s.color),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.info_outline, size: 16, color: BeldexColors.muted),
          ],
        ),
      ),
    );
  }
}

Future<void> showTxDetails(BuildContext context, Transfer tx) {
  final wallet = context.read<WalletService>();
  final daemonHeight = context.read<DaemonService>().info.height;
  final book = {for (final e in wallet.addressBook) e.address: e.name};
  final note = TextEditingController(text: tx.note);
  final s = txStyle(tx);
  final confirmations = tx.isPending
      ? 0
      : (tx.confirmations > 0 ? tx.confirmations : (daemonHeight - tx.height + 1).clamp(0, 1 << 30));
  return showBModal<void>(
    context,
    width: 480,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const H2('Transaction'),
              CopyPill(tx.txid),
              const SizedBox(height: 10),
              DetailLine('Type', Text(txLabel(tx), style: TextStyle(fontSize: 12, color: s.color))),
              DetailLine.text('Amount', '${s.sign}${formatBdx(tx.amount)} BDX'),
              if (tx.fee > 0) DetailLine.text('Fee', '${formatBdx(tx.fee)} BDX'),
              DetailLine(
                'Status',
                tx.type == 'failed'
                    ? const IconLabel(Icons.close, 'Failed', color: BeldexColors.red, size: 12)
                    : tx.isPending
                    ? const IconLabel(Icons.schedule, 'Pending', color: BeldexColors.amber, size: 12)
                    : const IconLabel(Icons.check, 'Confirmed', color: BeldexColors.green, size: 12),
              ),
              if (!tx.isPending) DetailLine.text('Confirmations', '$confirmations'),
              if (tx.height > 0) DetailLine.text('Block height', '${tx.height}'),
              if (tx.timestamp > 0) DetailLine.text('Date', formatTimestamp(tx.timestamp)),
              for (final d in tx.destinations)
                DetailLine.text(book['${d['address']}'] ?? 'To', shorten('${d['address']}', head: 10, tail: 10)),
              if (tx.isIncoming && tx.address.isNotEmpty)
                DetailLine.text(
                  tx.subaddrMinor == 0 ? 'To (primary)' : 'To subaddress #${tx.subaddrMinor}',
                  shorten(tx.address, head: 10, tail: 10),
                ),
              if (tx.paymentId.isNotEmpty && !RegExp(r'^0+$').hasMatch(tx.paymentId))
                DetailLine.text('Payment ID', shorten(tx.paymentId), last: true),
              const SizedBox(height: 12),
              Field(
                controller: note,
                hint: 'Add a note (only stored in this wallet)',
                onChanged: (_) => setState(() {}),
              ),
              ErrorText(error),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      'Explorer ↗',
                      onPressed: () => launchUrl(explorerUrl(wallet.netType, 'tx', tx.txid)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      note.text == tx.note ? 'Close' : 'Save note',
                      onPressed: () async {
                        if (note.text != tx.note) {
                          try {
                            await wallet.saveTxNote(tx.txid, note.text);
                          } catch (e) {
                            setState(() => error = errorText(e));
                            return;
                          }
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
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
  ).whenComplete(note.dispose);
}
