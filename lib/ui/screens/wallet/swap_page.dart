import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n.dart';
import '../../../services/swap/swap_models.dart';
import '../../../services/swap/swap_service.dart';
import '../../../services/wallet_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Privacy swaps are limited to these coins (plus BDX), as in the Electron wallet.
const _privacyCoins = {'XMR', 'ZEC', 'DASH', 'ROSE', 'DCR', 'ZEN', 'NYM', 'XVG', 'ARRR', 'DUSK', 'FIRO', 'VTC'};

/// Keeps the order being paid across tab switches.
final Expando<SwapOrder> _activeOrder = Expando();

class SwapPage extends StatelessWidget {
  const SwapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t('titles.swap.exchange')),
              Tab(text: t('titles.swap.history')),
            ],
          ),
          const Expanded(child: TabBarView(children: [_ExchangeTab(), _HistoryTab()])),
        ],
      ),
    );
  }
}

enum _Step { form, confirm, order }

class _ExchangeTab extends StatefulWidget {
  const _ExchangeTab();
  @override
  State<_ExchangeTab> createState() => _ExchangeTabState();
}

class _ExchangeTabState extends State<_ExchangeTab> {
  late final SwapService _swap = context.read<SwapService>();
  List<SwapCurrency> _currencies = const [];
  bool _loading = true;
  bool _maintenance = false;

  SwapCurrency? _from;
  SwapCurrency? _to;
  final _amount = TextEditingController(text: '0.01');
  bool _fixed = false;
  bool _privacy = false;

  SwapQuote? _quote;
  SwapLimits _limits = const SwapLimits();
  String? _quoteError;
  bool _quoting = false;
  Timer? _debounce;
  Timer? _refresh;

  final _recipient = TextEditingController();
  final _recipientExtra = TextEditingController();
  final _refund = TextEditingController();
  final _refundExtra = TextEditingController();
  bool? _recipientValid;
  bool? _refundValid;
  Timer? _recipientDebounce;
  Timer? _refundDebounce;
  bool _agree = false;

  _Step _step = _Step.form;
  SwapOrder? _order;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    final active = _activeOrder[_swap];
    if (active != null && !active.isTerminal) {
      _order = active;
      _step = _Step.order;
      _startStatusPolling();
    }
    _load();
  }

  @override
  void dispose() {
    for (final t in [_debounce, _refresh, _recipientDebounce, _refundDebounce, _statusTimer]) {
      t?.cancel();
    }
    for (final c in [_amount, _recipient, _recipientExtra, _refund, _refundExtra]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _swap.loadCurrencies(privacy: _privacy);
    if (!mounted) return;
    final bdx = list.where((c) => c.ticker == 'bdx').firstOrNull;
    final btc = list.where((c) => c.ticker == 'btc').firstOrNull;
    setState(() {
      _loading = false;
      _currencies = list;
      _maintenance = bdx == null || btc == null || !bdx.enabled;
      if (!_maintenance) {
        // Buy BDX with BTC when possible, otherwise sell BDX for BTC
        if (bdx!.enabledTo) {
          _from = btc;
          _to = bdx;
        } else {
          _from = bdx;
          _to = btc;
        }
        if (!_swap.supportsFixedRate) _fixed = false;
      }
    });
    if (!_maintenance) _requote();
  }

  List<SwapCurrency> get _options => _privacy
      ? _currencies.where((c) => c.ticker == 'bdx' || (c.enabled && _privacyCoins.contains(c.name))).toList()
      : _currencies.where((c) => c.enabled).toList();

  double? get _amountValue => double.tryParse(_amount.text);

  /// Quotes are fetched when the user stops typing, and refreshed every 30 s.
  void _requote({bool immediate = false}) {
    _debounce?.cancel();
    _refresh?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 400), () {
      _fetchQuote();
      _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _fetchQuote());
    });
  }

  Future<void> _fetchQuote() async {
    final from = _from, to = _to, amount = _amountValue;
    if (from == null || to == null || amount == null || amount <= 0) return;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final limitsFuture = _swap.limits(from, to, amount, privacy: _privacy).catchError((_) => const SwapLimits());
      final quote = _fixed
          ? await _swap.fixedQuote(from, to, amount, privacy: _privacy)
          : await _swap.quote(from, to, amount, privacy: _privacy);
      final limits = await limitsFuture;
      if (!mounted || from != _from || to != _to || amount != _amountValue) return;
      setState(() {
        _quote = quote;
        _limits = limits;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteError = errorText(e);
        if (e is SwapException && e.limits != null) _limits = e.limits!;
      });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  String? get _limitWarning {
    final amount = _amountValue ?? 0;
    final min = _fixed ? _limits.minFixed : _limits.minFloat;
    final max = _fixed ? _limits.maxFixed : _limits.maxFloat;
    if (min > 0 && amount < min) return '${t('titles.swap.minimumAmt')} $min ${_from?.name}';
    if (max > 0 && amount > max) return '${t('titles.swap.maximumAmt')} $max ${_from?.name}';
    return null;
  }

  void _validate({required bool refund}) {
    final controller = refund ? _refund : _recipient;
    final extra = refund ? _refundExtra : _recipientExtra;
    final currency = refund ? _from : _to;
    (refund ? _refundDebounce : _recipientDebounce)?.cancel();
    final value = controller.text.trim();
    if (value.isEmpty || currency == null) {
      setState(() => refund ? _refundValid = null : _recipientValid = null);
      return;
    }
    final timer = Timer(const Duration(milliseconds: 500), () async {
      final valid = await _swap.validateAddress(currency, value, extraId: extra.text.trim(), privacy: _privacy);
      if (!mounted || controller.text.trim() != value) return;
      setState(() => refund ? _refundValid = valid : _recipientValid = valid);
    });
    if (refund) {
      _refundDebounce = timer;
    } else {
      _recipientDebounce = timer;
    }
  }

  bool get _needsRefund => _swap.requiresRefundAddress(fixed: _fixed);

  bool get _canContinue =>
      _quote != null &&
      _quote!.amountTo > 0 &&
      _limitWarning == null &&
      _recipientValid == true &&
      (!_needsRefund || _refundValid == true) &&
      _agree;

  void _swapDirection() {
    setState(() {
      final f = _from;
      _from = _to;
      _to = f;
      _quote = null;
      _recipient.clear();
      _refund.clear();
      _recipientValid = null;
      _refundValid = null;
    });
    _requote(immediate: true);
  }

  Future<void> _pickCurrency({required bool from}) async {
    final picked = await showDialog<SwapCurrency>(
      context: context,
      builder: (_) => _CurrencyPicker(options: _options.where((c) => from ? c.enabledFrom : c.enabledTo).toList()),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
        if (picked == _to) _to = _currencies.firstWhere((c) => c.ticker == (picked.ticker == 'bdx' ? 'btc' : 'bdx'));
      } else {
        _to = picked;
        if (picked == _from)
          _from = _currencies.firstWhere((c) => c.ticker == (picked.ticker == 'bdx' ? 'btc' : 'bdx'));
      }
      // One side of every swap must be BDX
      if (_from!.ticker != 'bdx' && _to!.ticker != 'bdx') {
        if (from) {
          _to = _currencies.firstWhere((c) => c.ticker == 'bdx');
        } else {
          _from = _currencies.firstWhere((c) => c.ticker == 'bdx');
        }
      }
      if (!_from!.fixRateEnabled || !_to!.fixRateEnabled) _fixed = false;
      _quote = null;
      _recipient.clear();
      _refund.clear();
      _recipientValid = null;
      _refundValid = null;
    });
    _requote(immediate: true);
  }

  Future<void> _createOrder() async {
    final wallet = context.read<WalletService>();
    _refresh?.cancel();
    final order = await runWithProgress(
      context,
      () => _swap.createOrder(
        walletAddress: wallet.address,
        from: _from!,
        to: _to!,
        address: _recipient.text.trim(),
        amount: _amountValue!,
        extraId: _recipientExtra.text.trim(),
        refundAddress: _refund.text.trim(),
        refundExtraId: _refundExtra.text.trim(),
        fixedQuote: _fixed ? _quote : null,
        privacy: _privacy,
      ),
    );
    if (order == null || !mounted) return;
    _activeOrder[_swap] = order;
    setState(() {
      _order = order;
      _step = _Step.order;
    });
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    final order = _order;
    if (order == null) return;
    try {
      final updated = await _swap.refreshOrder(order, context.read<WalletService>().address);
      if (!mounted) return;
      _activeOrder[_swap] = updated;
      setState(() => _order = updated);
      if (updated.isTerminal) _statusTimer?.cancel();
    } catch (_) {}
  }

  void _newSwap() {
    _statusTimer?.cancel();
    _activeOrder[_swap] = null;
    setState(() {
      _order = null;
      _step = _Step.form;
      _agree = false;
      _recipient.clear();
      _refund.clear();
      _recipientExtra.clear();
      _refundExtra.clear();
      _recipientValid = null;
      _refundValid = null;
    });
    _requote(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_maintenance && _step == _Step.form) {
      return EmptyState(
        icon: Icons.construction,
        message: t('titles.swap.unsupportedpair'),
        hint: 'The swap service is under maintenance. Please try again later.',
      );
    }
    return switch (_step) {
      _Step.form => _buildForm(context),
      _Step.confirm => _buildConfirm(context),
      _Step.order => _OrderView(order: _order!, onNewSwap: _newSwap, onRefresh: _pollStatus),
    };
  }

  Widget _buildForm(BuildContext context) {
    final from = _from!, to = _to!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: t('titles.swap.swap'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_swap.active == Exchange.changelly) ...[
                Text(t('titles.swap.privacySwap')),
                Switch(
                  value: _privacy,
                  onChanged: (v) {
                    setState(() => _privacy = v);
                    _load();
                  },
                ),
              ],
              Chip(label: Text(_swap.active.name)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}'))],
                      onChanged: (_) {
                        setState(() {});
                        _requote();
                      },
                      decoration: InputDecoration(labelText: t('titles.swap.youSend'), errorText: _limitWarning),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CurrencyButton(currency: from, onTap: () => _pickCurrency(from: true)),
                ],
              ),
              Center(
                child: IconButton(onPressed: _swapDirection, icon: const Icon(Icons.swap_vert)),
              ),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: t('titles.swap.youGet')),
                      child: _quoting
                          ? const LinearProgressIndicator()
                          : Text(_quote == null ? '—' : '${_fixed ? '' : '≈ '}${_quote!.amountTo}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CurrencyButton(currency: to, onTap: () => _pickCurrency(from: false)),
                ],
              ),
              if (_quoteError != null) ...[
                const SizedBox(height: 8),
                Text(_quoteError!, style: const TextStyle(color: BeldexColors.negative)),
              ],
              const SizedBox(height: 16),
              if (_swap.supportsFixedRate && from.fixRateEnabled && to.fixRateEnabled)
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t('titles.swap.floatingExchangeRate'))),
                    ButtonSegment(value: true, label: Text(t('titles.swap.fixedExchangeRate'))),
                  ],
                  selected: {_fixed},
                  onSelectionChanged: (s) {
                    setState(() => _fixed = s.first);
                    _requote(immediate: true);
                  },
                ),
              if (_quote != null) ...[
                const SizedBox(height: 12),
                DetailRow(
                  t('titles.swap.exchangeRate'),
                  '1 ${from.name} ≈ ${(_quote!.amountTo / (_quote!.amountFrom == 0 ? 1 : _quote!.amountFrom)).toStringAsFixed(8)} ${to.name}',
                ),
                DetailRow(t('titles.swap.networkFee'), '${_quote!.networkFee} ${to.name}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: t('titles.swap.walletAddress'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _addressField(
                _recipient,
                '${to.name} ${t('fieldLabels.recipientAddress')}',
                _recipientValid,
                () => _validate(refund: false),
              ),
              if (to.needsExtraId) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _recipientExtra,
                  onChanged: (_) => _validate(refund: false),
                  decoration: InputDecoration(labelText: '${to.extraIdName} (${t('fieldLabels.optional')})'),
                ),
              ],
              if (_needsRefund) ...[
                const SizedBox(height: 16),
                _addressField(_refund, '${from.name} refund address', _refundValid, () => _validate(refund: true)),
                if (from.needsExtraId) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _refundExtra,
                    onChanged: (_) => _validate(refund: true),
                    decoration: InputDecoration(labelText: '${from.extraIdName} (${t('fieldLabels.optional')})'),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agree,
                onChanged: (v) => setState(() => _agree = v ?? false),
                title: Wrap(
                  children: [
                    Text('${t('titles.swap.agreeWith')} '),
                    InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(
                          _swap.active == Exchange.changelly
                              ? 'https://changelly.com/terms-of-use'
                              : 'https://quickex.io/terms-of-use',
                        ),
                      ),
                      child: Text(t('titles.swap.termOfUse'), style: const TextStyle(color: BeldexColors.blue)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _canContinue ? () => setState(() => _step = _Step.confirm) : null,
                  child: Text(t('buttons.next')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _addressField(TextEditingController c, String label, bool? valid, VoidCallback onChanged) => TextField(
    controller: c,
    onChanged: (_) => onChanged(),
    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      errorText: valid == false ? t('notification.errors.invalidAddress') : null,
      suffixIcon: valid == true ? const Icon(Icons.check_circle, color: BeldexColors.green) : null,
    ),
  );

  Widget _buildConfirm(BuildContext context) {
    final q = _quote!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: t('titles.swap.checkout'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailRow(t('titles.swap.youSend'), '${_amountValue} ${_from!.name}'),
              DetailRow(t('titles.swap.youGet'), '${_fixed ? '' : '≈ '}${q.amountTo} ${_to!.name}'),
              DetailRow(
                t('titles.swap.exchangeRate'),
                _fixed ? t('titles.swap.fixedRate') : t('titles.swap.floatingExchangeRate'),
              ),
              DetailRow(t('titles.swap.networkFee'), '${q.networkFee} ${_to!.name}'),
              DetailRow(t('fieldLabels.recipientAddress'), _recipient.text.trim(), mono: true),
              if (_refund.text.trim().isNotEmpty) DetailRow('Refund address', _refund.text.trim(), mono: true),
              const SizedBox(height: 8),
              Text(
                _fixed ? t('titles.swap.fixedRateExactAmtDisc') : t('titles.swap.floatingRateDisc'),
                style: const TextStyle(color: BeldexColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => setState(() => _step = _Step.form), child: Text(t('buttons.back'))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _createOrder, child: Text(t('titles.swap.checkout'))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyButton extends StatelessWidget {
  const _CurrencyButton({required this.currency, required this.onTap});
  final SwapCurrency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    height: 56,
    child: OutlinedButton(
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text('${currency.name} · ${currency.protocol.toUpperCase()}', overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    ),
  );
}

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker({required this.options});
  final List<SwapCurrency> options;
  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = widget.options
        .where((c) => q.isEmpty || c.ticker.contains(q) || c.fullName.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: TextField(
        autofocus: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
      content: SizedBox(
        width: 420,
        height: 480,
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(list[i].name),
            subtitle: Text('${list[i].fullName} · ${list[i].protocol}'),
            onTap: () => Navigator.pop(context, list[i]),
          ),
        ),
      ),
    );
  }
}

/// Deposit instructions + live status for a created order.
class _OrderView extends StatelessWidget {
  const _OrderView({required this.order, required this.onNewSwap, required this.onRefresh});
  final SwapOrder order;
  final VoidCallback onNewSwap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final finished = order.status == 'finished';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionCard(
          title: finished ? 'Swap completed' : 'Send ${order.amountFrom} ${order.currencyFrom.toUpperCase()}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(label: Text(order.status.toUpperCase())),
              IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!finished && order.payinAddress.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(data: order.payinAddress, size: 150),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DetailRow('Deposit address', order.payinAddress, copyable: true, mono: true),
                          if (order.payinExtraId.isNotEmpty)
                            DetailRow('Memo / Extra ID', order.payinExtraId, copyable: true),
                          _Countdown(order: order),
                        ],
                      ),
                    ),
                  ],
                ),
              const Divider(height: 32),
              DetailRow('Order ID', order.id, copyable: true, mono: true),
              DetailRow(
                t('titles.swap.youGet'),
                '${order.status == 'finished' ? '' : '≈ '}${order.amountTo} ${order.currencyTo.toUpperCase()}',
              ),
              DetailRow(t('fieldLabels.recipientAddress'), order.payoutAddress, mono: true),
              if (order.payinHash.isNotEmpty) DetailRow('Input hash', order.payinHash, copyable: true, mono: true),
              if (order.payoutHash.isNotEmpty) DetailRow('Output hash', order.payoutHash, copyable: true, mono: true),
              if (order.confirmations != null)
                Text(
                  'The exchange needs ${order.confirmations} confirmations of your deposit.',
                  style: const TextStyle(color: BeldexColors.muted, fontSize: 12),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: onNewSwap, child: const Text('New swap')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.order});
  final SwapOrder order;
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final deadline = o.type == 'fixed' && o.payTill != null
        ? DateTime.tryParse(o.payTill!) ?? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(o.createdAtMs).add(const Duration(hours: 3));
    final left = deadline.difference(DateTime.now());
    final text = left.isNegative
        ? 'Expired'
        : '${left.inHours}h ${left.inMinutes.remainder(60)}m ${left.inSeconds.remainder(60)}s';
    return DetailRow('Time left', text);
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  static const _pageSize = 7;
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final swap = context.read<SwapService>();
    final address = context.select<WalletService, String>((w) => w.address);
    final history = swap.history(address, page: _page, pageSize: _pageSize);
    final pages = (history.total / _pageSize).ceil();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${history.total} swaps', style: const TextStyle(color: BeldexColors.muted)),
              const Spacer(),
              IconButton(
                tooltip: 'CSV',
                icon: const Icon(Icons.download),
                onPressed: history.total == 0
                    ? null
                    : () async {
                        final location = await getSaveLocation(
                          suggestedName: 'Beldex_wallet_swap_transaction_report.csv',
                        );
                        if (location == null) return;
                        await File(location.path).writeAsString(swap.historyCsv(address));
                        if (context.mounted) {
                          showSnack(
                            context,
                            t('notification.positive.itemSaved', {'item': 'CSV Report', 'filename': location.path}),
                          );
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: history.orders.isEmpty
                ? EmptyState(icon: Icons.swap_horiz, message: t('strings.noTransactionsFound'))
                : Card(
                    child: ListView.separated(
                      itemCount: history.orders.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, i) {
                        final o = history.orders[i];
                        return ListTile(
                          title: Text('${o.currencyFrom.toUpperCase()} → ${o.currencyTo.toUpperCase()}'),
                          subtitle: Text(
                            '${DateTime.fromMillisecondsSinceEpoch(o.createdAtMs).toLocal().toString().substring(0, 16)} · ${o.exchange.name}${o.privacySwap ? ' · privacy' : ''}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${o.amountFrom} → ${o.status == 'finished' ? '' : '≈ '}${o.amountTo.toStringAsFixed(4)}',
                              ),
                              Text(
                                o.status,
                                style: TextStyle(
                                  color: o.status == 'finished' ? BeldexColors.greenBright : BeldexColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _details(context, o, address),
                        );
                      },
                    ),
                  ),
          ),
          if (pages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 1 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_page / $pages'),
                IconButton(
                  onPressed: _page < pages ? () => setState(() => _page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _details(BuildContext context, SwapOrder order, String address) async {
    final swap = context.read<SwapService>();
    var current = order;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('titles.swap.transactionDetails')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(child: _OrderDetails(order: current)),
          ),
          actions: [
            if (!current.isTerminal)
              TextButton(
                onPressed: () async {
                  try {
                    final updated = await swap.refreshOrder(current, address);
                    setState(() => current = updated);
                  } catch (e) {
                    if (ctx.mounted) showError(ctx, e);
                  }
                },
                child: Text(t('buttons.refresh')),
              ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('buttons.close'))),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({required this.order});
  final SwapOrder order;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DetailRow('Order ID', order.id, copyable: true, mono: true),
      DetailRow('Status', order.status),
      DetailRow('Exchange', order.exchange.name),
      DetailRow(t('titles.swap.youSend'), '${order.amountFrom} ${order.currencyFrom.toUpperCase()}'),
      DetailRow(t('titles.swap.youGet'), '${order.amountTo} ${order.currencyTo.toUpperCase()}'),
      DetailRow(t('titles.swap.exchangeRate'), order.rate.toStringAsFixed(8)),
      DetailRow('Deposit address', order.payinAddress, copyable: true, mono: true),
      DetailRow(t('fieldLabels.recipientAddress'), order.payoutAddress, copyable: true, mono: true),
      if (order.refundAddress.isNotEmpty) DetailRow('Refund address', order.refundAddress, mono: true),
      if (order.payinHash.isNotEmpty) DetailRow('Input hash', order.payinHash, copyable: true, mono: true),
      if (order.payoutHash.isNotEmpty) DetailRow('Output hash', order.payoutHash, copyable: true, mono: true),
    ],
  );
}
