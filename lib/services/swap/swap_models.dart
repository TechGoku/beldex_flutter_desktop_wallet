/// Exchange-neutral swap models (both adapters normalise into these).

enum Exchange { changelly, quickex }

class SwapCurrency {
  SwapCurrency({
    required this.ticker,
    required this.name,
    required this.fullName,
    required this.protocol,
    required this.enabled,
    required this.enabledFrom,
    required this.enabledTo,
    required this.fixRateEnabled,
    required this.payinConfirmations,
    this.extraIdName,
    this.image = '',
  });

  final String ticker;
  final String name;
  final String fullName;
  final String protocol;
  final bool enabled;
  final bool enabledFrom;
  final bool enabledTo;
  final bool fixRateEnabled;
  final int payinConfirmations;
  final String? extraIdName;
  final String image;

  bool get needsExtraId => extraIdName != null && extraIdName!.isNotEmpty;

  @override
  bool operator ==(Object other) => other is SwapCurrency && other.ticker == ticker && other.protocol == protocol;
  @override
  int get hashCode => Object.hash(ticker, protocol);
}

class SwapQuote {
  SwapQuote({required this.amountFrom, required this.amountTo, this.rate, this.networkFee = 0, this.rateId});
  final double amountFrom;
  final double amountTo;
  final double? rate;
  final double networkFee;

  /// Fixed-rate quote id (Changelly only).
  final String? rateId;
}

class SwapLimits {
  const SwapLimits({this.minFloat = 0, this.maxFloat = 0, this.minFixed = 0, this.maxFixed = 0});
  final double minFloat;
  final double maxFloat;
  final double minFixed;
  final double maxFixed;
}

class SwapOrder {
  SwapOrder(this.raw, this.exchange);
  final Map<String, dynamic> raw;
  final Exchange exchange;

  String get id => '${raw['id'] ?? ''}';
  String get status => raw['status'] as String? ?? 'waiting';
  String get type => raw['type'] as String? ?? 'float';
  String get currencyFrom => (raw['currencyFrom'] as String? ?? '').toLowerCase();
  String get currencyTo => (raw['currencyTo'] as String? ?? '').toLowerCase();
  String get payinAddress => raw['payinAddress'] as String? ?? '';
  String get payinExtraId => raw['payinExtraId'] as String? ?? '';
  String get payoutAddress => raw['payoutAddress'] as String? ?? '';
  String get refundAddress => raw['refundAddress'] as String? ?? '';
  double get amountFrom => _num(raw['amountExpectedFrom'] ?? raw['amountFrom']);
  double get amountTo => _num(raw['amountExpectedTo'] ?? raw['amountTo']);
  double get networkFee => _num(raw['networkFee']);
  double get rate {
    final r = _num(raw['rate']);
    if (r > 0) return r;
    return amountFrom > 0 ? amountTo / amountFrom : 0;
  }

  String get payinHash => raw['payinHash'] as String? ?? '';
  String get payoutHash => raw['payoutHash'] as String? ?? raw['payoutHashLink'] as String? ?? '';
  int get createdAtMs => _ms(raw['createdAt'] ?? raw['created_at']);
  String? get payTill => raw['payTill'] as String?;
  bool get privacySwap => raw['privacySwap'] == true;
  int? get confirmations => (raw['payinConfirmations'] as num?)?.toInt();

  static const terminalStatuses = {'finished', 'failed', 'refunded', 'expired', 'overdue'};
  bool get isTerminal => terminalStatuses.contains(status);

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static int _ms(Object? v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    if (v is String && int.tryParse(v) == null) {
      return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    }
    final n = v is num ? v.toInt() : int.parse('$v');
    final digits = n.abs().toString().length;
    if (digits >= 16) return n ~/ 1000;
    if (digits <= 10) return n * 1000;
    return n;
  }
}

class SwapException implements Exception {
  SwapException(this.message, {this.limits});
  final String message;

  /// Min/max hint parsed from an "amount too small/big" error.
  final SwapLimits? limits;
  @override
  String toString() => message;
}
