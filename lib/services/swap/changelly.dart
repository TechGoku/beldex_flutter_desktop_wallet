import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'swap_models.dart';

/// Changelly API v2 (JSON-RPC, requests signed with an RSA private key).
///
/// Keys are provided at build time, as in the Electron wallet:
///   --dart-define=CHANGELLY_SWAP_API_KEY=... --dart-define=CHANGELLY_SWAP_PRIVATE_KEY=<pkcs8 der hex>
///   (and the CHANGELLY_PRIVACY_SWAP_* pair for privacy swaps)
class ChangellyClient {
  ChangellyClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _url = 'https://api.changelly.com/v2';
  static const _apiKey = String.fromEnvironment('CHANGELLY_SWAP_API_KEY');
  static const _privateKey = String.fromEnvironment('CHANGELLY_SWAP_PRIVATE_KEY');
  static const _privacyApiKey = String.fromEnvironment('CHANGELLY_PRIVACY_SWAP_API_KEY');
  static const _privacyPrivateKey = String.fromEnvironment('CHANGELLY_PRIVACY_SWAP_PRIVATE_KEY');

  static bool get configured => _apiKey.isNotEmpty && _privateKey.isNotEmpty;

  final Map<String, RSAPrivateKey> _keys = {};

  Future<dynamic> _post(String method, Map<String, dynamic> params, {bool privacy = false}) async {
    final apiKey = privacy && _privacyApiKey.isNotEmpty ? _privacyApiKey : _apiKey;
    final keyHex = privacy && _privacyPrivateKey.isNotEmpty ? _privacyPrivateKey : _privateKey;
    if (apiKey.isEmpty || keyHex.isEmpty) {
      throw SwapException('Changelly API keys are not configured in this build');
    }
    final body = jsonEncode({'jsonrpc': '2.0', 'id': 'beldex', 'method': method, 'params': params});
    final signature = _sign(keyHex, utf8.encode(body));
    final response = await _http
        .post(
          Uri.parse(_url),
          headers: {'Content-Type': 'application/json', 'X-Api-Key': apiKey, 'X-Api-Signature': signature},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      final error = decoded['error'];
      throw SwapException(error is Map ? '${error['message']}' : '$error');
    }
    return decoded['result'];
  }

  String _sign(String keyHex, List<int> data) {
    final key = _keys[keyHex] ??= _parsePkcs8(_hexToBytes(keyHex));
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final sig = signer.generateSignature(Uint8List.fromList(data));
    return base64Encode(sig.bytes);
  }

  static Uint8List _hexToBytes(String hex) =>
      Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

  /// PKCS#8 PrivateKeyInfo -> RSAPrivateKey
  static RSAPrivateKey _parsePkcs8(Uint8List der) {
    final info = ASN1Parser(der).nextObject() as ASN1Sequence;
    final octets = info.elements![2] as ASN1OctetString;
    final rsa = ASN1Parser(octets.valueBytes!).nextObject() as ASN1Sequence;
    BigInt n(int i) => (rsa.elements![i] as ASN1Integer).integer!;
    return RSAPrivateKey(n(1), n(3), n(4), n(5));
  }

  Future<List<SwapCurrency>> currencies({bool privacy = false}) async {
    final result = await _post('getCurrenciesFull', {}, privacy: privacy) as List;
    return [
      for (final c in result.cast<Map<String, dynamic>>())
        SwapCurrency(
          ticker: (c['ticker'] ?? c['name'] ?? '').toString().toLowerCase(),
          name: (c['ticker'] ?? c['name'] ?? '').toString().toUpperCase(),
          fullName: '${c['fullName'] ?? c['name'] ?? ''}',
          protocol: '${c['protocol'] ?? c['contractAddress'] ?? ''}',
          enabled: c['enabled'] == true,
          enabledFrom: c['enabledFrom'] == true,
          enabledTo: c['enabledTo'] == true,
          fixRateEnabled: c['fixRateEnabled'] == true,
          payinConfirmations: (c['payinConfirmations'] as num?)?.toInt() ?? 0,
          extraIdName: c['extraIdName'] as String?,
          image: '${c['image'] ?? ''}',
        ),
    ];
  }

  Future<SwapQuote> quote(String from, String to, double amount, {bool privacy = false}) async {
    final r = await _post('getExchangeAmount', {'from': from, 'to': to, 'amountFrom': '$amount'}, privacy: privacy);
    final q = (r as List).first as Map<String, dynamic>;
    return SwapQuote(
      amountFrom: double.tryParse('${q['amountFrom']}') ?? amount,
      amountTo: double.tryParse('${q['amountTo'] ?? q['result']}') ?? 0,
      rate: double.tryParse('${q['rate']}'),
      networkFee: double.tryParse('${q['networkFee']}') ?? 0,
    );
  }

  Future<SwapQuote> fixedQuote(String from, String to, double amount, {bool privacy = false}) async {
    final r = await _post('getFixRateForAmount', {'from': from, 'to': to, 'amountFrom': '$amount'}, privacy: privacy);
    final q = (r as List).first as Map<String, dynamic>;
    return SwapQuote(
      amountFrom: double.tryParse('${q['amountFrom']}') ?? amount,
      amountTo: double.tryParse('${q['amountTo']}') ?? 0,
      rate: double.tryParse('${q['result']}'),
      networkFee: double.tryParse('${q['networkFee']}') ?? 0,
      rateId: q['id'] as String?,
    );
  }

  Future<SwapLimits> limits(String from, String to, {bool privacy = false}) async {
    final r = await _post('getPairsParams', {'from': from, 'to': to}, privacy: privacy);
    final q = (r as List).first as Map<String, dynamic>;
    double d(String k) => double.tryParse('${q[k]}') ?? 0;
    return SwapLimits(
      minFloat: d('minAmountFloat'),
      maxFloat: d('maxAmountFloat'),
      minFixed: d('minAmountFixed'),
      maxFixed: d('maxAmountFixed'),
    );
  }

  Future<bool> validateAddress(String currency, String address, {String? extraId, bool privacy = false}) async {
    final r = await _post('validateAddress', {
      'currency': currency,
      'address': address,
      if (extraId != null && extraId.isNotEmpty) 'extraId': extraId,
    }, privacy: privacy);
    return r is Map && r['result'] == true;
  }

  Future<SwapOrder> createOrder({
    required String from,
    required String to,
    required String address,
    required double amount,
    String? extraId,
    String? refundAddress,
    String? refundExtraId,
    String? rateId,
    bool privacy = false,
  }) async {
    final fixed = rateId != null;
    final r = await _post(fixed ? 'createFixTransaction' : 'createTransaction', {
      'from': from,
      'to': to,
      'address': address,
      'amountFrom': '$amount',
      if (extraId?.isNotEmpty ?? false) 'extraId': extraId,
      if (refundAddress?.isNotEmpty ?? false) 'refundAddress': refundAddress,
      if (refundExtraId?.isNotEmpty ?? false) 'refundExtraId': refundExtraId,
      if (fixed) 'rateId': rateId,
    }, privacy: privacy);
    return SwapOrder({...(r as Map).cast<String, dynamic>(), 'privacySwap': privacy}, Exchange.changelly);
  }

  Future<List<SwapOrder>> orders(List<String> ids, {bool privacy = false}) async {
    final r = await _post('getTransactions', {'id': ids}, privacy: privacy);
    return [for (final o in (r as List).cast<Map<String, dynamic>>()) SwapOrder(o, Exchange.changelly)];
  }
}
