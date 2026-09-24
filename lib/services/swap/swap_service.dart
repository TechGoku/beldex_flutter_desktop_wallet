import 'swap_models.dart';
import 'changelly.dart';
import 'quickex.dart';
import 'swap_store.dart';

/// Picks an exchange that currently supports BDX and routes calls to it.
class SwapService {
  SwapService({ChangellyClient? changelly, QuickexClient? quickex, SwapStore? store})
    : changelly = changelly ?? ChangellyClient(),
      quickex = quickex ?? QuickexClient(),
      store = store ?? SwapStore();

  final ChangellyClient changelly;
  final QuickexClient quickex;
  final SwapStore store;

  Exchange active = Exchange.changelly;

  static bool _hasBdx(List<SwapCurrency> list) => list.any((c) => c.ticker == 'bdx' && c.enabled);

  /// Returns the currency list of the first exchange that lists BDX, or an
  /// empty list (maintenance) when none does.
  Future<List<SwapCurrency>> loadCurrencies({bool privacy = false}) async {
    if (ChangellyClient.configured) {
      try {
        final list = await changelly.currencies(privacy: privacy);
        if (_hasBdx(list)) {
          active = Exchange.changelly;
          return list..sort((a, b) => a.name.compareTo(b.name));
        }
      } catch (_) {}
    }
    try {
      final list = await quickex.currencies();
      if (_hasBdx(list)) {
        active = Exchange.quickex;
        return list..sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (_) {}
    return const [];
  }

  bool get supportsFixedRate => active == Exchange.changelly;

  /// QuickEx always needs a refund address; Changelly only for fixed rate.
  bool requiresRefundAddress({required bool fixed}) => active == Exchange.quickex || fixed;

  Future<SwapQuote> quote(SwapCurrency from, SwapCurrency to, double amount, {bool privacy = false}) =>
      active == Exchange.changelly
      ? changelly.quote(from.ticker, to.ticker, amount, privacy: privacy)
      : quickex.quote(from, to, amount);

  Future<SwapQuote> fixedQuote(SwapCurrency from, SwapCurrency to, double amount, {bool privacy = false}) {
    if (active != Exchange.changelly) {
      throw SwapException('Fixed-rate swaps are not available on QuickEx');
    }
    return changelly.fixedQuote(from.ticker, to.ticker, amount, privacy: privacy);
  }

  Future<SwapLimits> limits(SwapCurrency from, SwapCurrency to, double amount, {bool privacy = false}) =>
      active == Exchange.changelly
      ? changelly.limits(from.ticker, to.ticker, privacy: privacy)
      : quickex.limits(from, to, amount);

  Future<bool> validateAddress(SwapCurrency currency, String address, {String? extraId, bool privacy = false}) async {
    try {
      return active == Exchange.changelly
          ? await changelly.validateAddress(currency.ticker, address, extraId: extraId, privacy: privacy)
          : await quickex.validateAddress(currency, address, extraId: extraId);
    } catch (_) {
      return false;
    }
  }

  Future<SwapOrder> createOrder({
    required String walletAddress,
    required SwapCurrency from,
    required SwapCurrency to,
    required String address,
    required double amount,
    String? extraId,
    String? refundAddress,
    String? refundExtraId,
    SwapQuote? fixedQuote,
    bool privacy = false,
  }) async {
    final order = active == Exchange.changelly
        ? await changelly.createOrder(
            from: from.ticker,
            to: to.ticker,
            address: address,
            amount: amount,
            extraId: extraId,
            refundAddress: refundAddress,
            refundExtraId: refundExtraId,
            rateId: fixedQuote?.rateId,
            privacy: privacy,
          )
        : await quickex.createOrder(
            from: from,
            to: to,
            address: address,
            amount: amount,
            extraId: extraId,
            refundAddress: refundAddress,
            refundExtraId: refundExtraId,
          );
    final stamped = SwapOrder({...order.raw, 'createdAt': DateTime.now().millisecondsSinceEpoch}, order.exchange);
    store.upsert(stamped, walletAddress, networkFrom: from.protocol, networkTo: to.protocol);
    return stamped;
  }

  /// Fetches the latest status and persists it.
  Future<SwapOrder> refreshOrder(SwapOrder order, String walletAddress) async {
    SwapOrder latest;
    if (order.exchange == Exchange.quickex) {
      latest = await quickex.order(order.id, order.payoutAddress);
    } else {
      final list = await changelly.orders([order.id], privacy: order.privacySwap);
      if (list.isEmpty) return order;
      latest = list.first;
    }
    final merged = SwapOrder({
      ...order.raw,
      ...latest.raw..removeWhere((k, v) => v == null || v == ''),
      'createdAt': order.raw['createdAt'],
      'privacySwap': order.privacySwap,
    }, order.exchange);
    store.upsert(merged, walletAddress);
    return merged;
  }

  ({List<SwapOrder> orders, int total}) history(String walletAddress, {int page = 1, int pageSize = 7}) =>
      (orders: store.page(walletAddress, page: page, pageSize: pageSize), total: store.count(walletAddress));

  String historyCsv(String walletAddress) {
    String esc(Object? v) {
      final s = '${v ?? ''}'.replaceAll('"', '""');
      return s.contains(',') || s.contains('"') || s.contains('\n') ? '"$s"' : s;
    }

    final rows = [
      'Date,Status,Exchange_Currency,Exchange_Amount,Exchange_rate,Received_Amount,Swap_Type,Receiver_Address',
      for (final o in store.all(walletAddress))
        [
          DateTime.fromMillisecondsSinceEpoch(o.createdAtMs).toIso8601String(),
          o.status,
          '${o.currencyFrom.toUpperCase()} -> ${o.currencyTo.toUpperCase()}',
          o.amountFrom,
          o.rate,
          o.amountTo,
          o.privacySwap ? 'Privacy' : 'Normal',
          o.payoutAddress,
        ].map(esc).join(','),
    ];
    return rows.join('\r\n');
  }
}
