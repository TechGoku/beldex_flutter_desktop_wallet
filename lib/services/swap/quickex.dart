import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'swap_models.dart';

/// QuickEx REST API. Order creation/status use HMAC-SHA256 signed headers.
///   --dart-define=QUICKEX_SWAP_PUPLIC_KEY=... --dart-define=QUICKEX_SWAP_SECRET_KEY=...
///   --dart-define=QUICKEX_REFERRER_ID=...
class QuickexClient {
  QuickexClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _base = 'https://quickex.io/api';
  static const _publicKey = String.fromEnvironment('QUICKEX_SWAP_PUPLIC_KEY');
  static const _secretKey = String.fromEnvironment('QUICKEX_SWAP_SECRET_KEY');
  static const _referrerId = String.fromEnvironment('QUICKEX_REFERRER_ID');

  static bool get configured => _publicKey.isNotEmpty && _secretKey.isNotEmpty;

  static const _jsonHeaders = {'Accept': 'application/json', 'Content-Type': 'application/json'};

  Map<String, String> _auth(String payloadBody) {
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    final mac = Hmac(sha256, utf8.encode(_secretKey)).convert(utf8.encode('$timestamp$payloadBody$_publicKey'));
    return {'X-Api-Public-Key': _publicKey, 'X-Api-Timestamp': timestamp, 'X-Api-Signature': base64Encode(mac.bytes)};
  }

  Future<dynamic> _decode(http.Response response) async {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) throw _error(body);
    return body;
  }

  SwapException _error(dynamic body) {
    final message = body is Map ? '${body['message'] ?? body['error'] ?? 'QuickEx error'}' : 'QuickEx error';
    final details = body is Map ? (body['data']?['details'] ?? body['details'] ?? body['data'] ?? body) : null;
    final expected = details is Map ? (details['expectedGeneral'] ?? details['expected']) : null;
    final exp = expected != null
        ? double.tryParse('$expected')
        : double.tryParse(
            RegExp(r'expected[:\s]+(\d+\.?\d*)', caseSensitive: false).firstMatch(message)?.group(1) ?? '',
          );
    if (exp != null) {
      final tooSmall = message.contains('Amount Too Small');
      return SwapException(
        '$message. Expected: $exp',
        limits: tooSmall ? SwapLimits(minFloat: exp, minFixed: exp) : SwapLimits(maxFloat: exp, maxFixed: exp),
      );
    }
    return SwapException(message);
  }

  Future<List<SwapCurrency>> currencies() async {
    final r = await _decode(await _http.get(Uri.parse('$_base/v2/instruments/public'), headers: _jsonHeaders)) as List;
    return [
      for (final c in r.cast<Map<String, dynamic>>())
        SwapCurrency(
          ticker: '${c['currencyTitle'] ?? ''}'.toLowerCase(),
          name: '${c['currencyTitle'] ?? ''}'.toUpperCase(),
          fullName: '${c['fullName'] ?? c['currencyFriendlyTitle'] ?? c['currencyTitle'] ?? ''}',
          protocol: '${c['networkTitle'] ?? ''}',
          enabled: true,
          enabledFrom: true,
          enabledTo: true,
          fixRateEnabled: false,
          payinConfirmations: 3,
          extraIdName: c['requiresMemo'] == true ? 'memo' : null,
          image: '${c['currencyLogoLink'] ?? ''}',
        ),
    ];
  }

  Uri _rateUri(SwapCurrency from, SwapCurrency to, double amount) => Uri.parse('$_base/v2/rates/public/one').replace(
    queryParameters: {
      'instrumentFromCurrencyTitle': from.ticker.toUpperCase(),
      'instrumentFromNetworkTitle': from.protocol.toUpperCase(),
      'instrumentToCurrencyTitle': to.ticker.toUpperCase(),
      'instrumentToNetworkTitle': to.protocol.toUpperCase(),
      'claimedDepositAmountCurrency': from.ticker.toUpperCase(),
      'claimedDepositAmount': '$amount',
      'rateMode': 'FLOATING',
      'exchangeType': 'crypto',
      'referrerId': _referrerId,
    },
  );

  Future<SwapQuote> quote(SwapCurrency from, SwapCurrency to, double amount) async {
    final r = await _decode(await _http.get(_rateUri(from, to, amount), headers: _jsonHeaders)) as Map;
    return SwapQuote(
      amountFrom: amount,
      amountTo: double.tryParse('${r['amountToGet']}') ?? 0,
      rate: double.tryParse('${r['price']}'),
      networkFee: double.tryParse('${r['finalNetworkFeeAmount'] ?? r['networkFee'] ?? 0}') ?? 0,
    );
  }

  Future<SwapLimits> limits(SwapCurrency from, SwapCurrency to, double amount) async {
    final r = await _decode(await _http.get(_rateUri(from, to, amount), headers: _jsonHeaders)) as Map;
    final min = double.tryParse('${r['generalMinAmount']}') ?? 0;
    final max = double.tryParse('${r['generalMaxAmount']}') ?? 0;
    return SwapLimits(minFloat: min, maxFloat: max, minFixed: min, maxFixed: max);
  }

  Future<bool> validateAddress(SwapCurrency currency, String address, {String? extraId}) async {
    final r = await _decode(
      await _http.post(
        Uri.parse('$_base/v1/instruments/public/validate-address'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'currencyTitle': currency.ticker.toUpperCase(),
          'networkTitle': currency.protocol.toUpperCase(),
          'address': address,
          if (extraId?.isNotEmpty ?? false) 'memo': extraId,
        }),
      ),
    );
    return r == true || (r is Map && r['result'] == true);
  }

  Future<SwapOrder> createOrder({
    required SwapCurrency from,
    required SwapCurrency to,
    required String address,
    required double amount,
    String? extraId,
    String? refundAddress,
    String? refundExtraId,
  }) async {
    final body = {
      'instrumentFrom': {'currencyTitle': from.ticker.toUpperCase(), 'networkTitle': from.protocol.toUpperCase()},
      'instrumentTo': {'currencyTitle': to.ticker.toUpperCase(), 'networkTitle': to.protocol.toUpperCase()},
      'destinationAddress': address,
      'refundAddress': refundAddress ?? '',
      'claimedDepositAmount': '$amount',
      'referrerId': _referrerId,
      if (extraId?.isNotEmpty ?? false) 'destinationAddressMemo': extraId,
      if (refundExtraId?.isNotEmpty ?? false) 'refundAddressMemo': refundExtraId,
    };
    final encoded = jsonEncode(body);
    final r = await _decode(
      await _http.post(
        Uri.parse('$_base/v2/orders/public/create'),
        headers: {..._jsonHeaders, ..._auth(encoded)},
        body: encoded,
      ),
    ) as Map<String, dynamic>;
    return _normalise(r);
  }

  Future<SwapOrder> order(String orderId, String destinationAddress) async {
    final query = 'orderId=$orderId&destinationAddress=${Uri.encodeQueryComponent(destinationAddress)}';
    final r = await _decode(
      await _http.get(Uri.parse('$_base/v2/orders/public-info?$query'), headers: {..._jsonHeaders, ..._auth(query)}),
    ) as Map<String, dynamic>;
    return _normalise(r);
  }

  static const _eventStatus = {
    'CREATION_END': 'waiting',
    'INCOMING_FUNDS_DETECTED': 'confirming',
    'DEPOSIT_REGISTERED': 'exchanging',
    'FUNDS_WITHDRAWAL_START': 'sending',
    'WITHDRAWAL_COMPLETED': 'finished',
  };

  static String _status(Map<String, dynamic> tx) {
    if (tx['completed'] == true) return 'finished';
    if (tx['failedToCreate'] == true) return 'failed';
    final events = tx['orderEvents'] as List?;
    if (events != null && events.isNotEmpty) {
      final event = events.first as Map;
      final created = DateTime.tryParse('${event['createdAt']}');
      if (created != null && DateTime.now().difference(created) > const Duration(hours: 3)) return 'overdue';
      return _eventStatus[event['kind']] ?? 'waiting';
    }
    return 'waiting';
  }

  static String _addr(Object? v, String key) => v is String ? v : (v is Map ? '${v[key] ?? v['address'] ?? ''}' : '');

  SwapOrder _normalise(Map<String, dynamic> tx) {
    final deposits = (tx['deposits'] as List?) ?? const [];
    final withdrawals = (tx['withdrawals'] as List?) ?? const [];
    return SwapOrder({
      'id': tx['orderId'] ?? tx['id'],
      'status': _status(tx),
      'type': 'float',
      'currencyFrom': '${tx['instrumentFromCurrencyTitle'] ?? ''}',
      'currencyTo': '${tx['instrumentToCurrencyTitle'] ?? ''}',
      'payinAddress': _addr(tx['depositAddress'], 'depositAddress'),
      'payinExtraId': _addr(tx['depositAddress'], 'depositAddressMemo'),
      'payoutAddress': _addr(tx['destinationAddress'], 'destinationAddress'),
      'refundAddress': _addr(tx['refundAddress'], 'refundAddress'),
      'amountExpectedFrom': tx['claimedDepositAmount'],
      'amountExpectedTo': tx['amountToGet'],
      'networkFee': tx['claimedNetworkFee'] ?? 0,
      'rate': tx['price'],
      'payinHash': deposits.isNotEmpty ? (deposits.first as Map)['txId'] : '',
      'payoutHash': withdrawals.isNotEmpty ? (withdrawals.first as Map)['txId'] : '',
      'createdAt': tx['createdAt'],
      'payTill': DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
      'payinConfirmations': tx['minConfirmationsToTrade'] ?? 3,
      'raw_response': tx,
    }, Exchange.quickex);
  }
}
