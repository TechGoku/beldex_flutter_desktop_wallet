import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// BDX/USD price from CoinGecko, cached for 60 s (same source as the
/// Beldex browser extension). Purely informational; failures are silent.
class PriceService extends ChangeNotifier {
  double? usd;
  DateTime _fetched = DateTime.fromMillisecondsSinceEpoch(0);
  bool _inFlight = false;

  Future<void> refresh() async {
    if (_inFlight || DateTime.now().difference(_fetched) < const Duration(seconds: 60)) return;
    _inFlight = true;
    try {
      final r = await http
          .get(Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=beldex&vs_currencies=usd'))
          .timeout(const Duration(seconds: 10));
      final value = (jsonDecode(r.body) as Map)['beldex']?['usd'];
      if (value is num) {
        usd = value.toDouble();
        _fetched = DateTime.now();
        notifyListeners();
      }
    } catch (_) {
      // Offline or rate-limited: keep the last known price
    } finally {
      _inFlight = false;
    }
  }
}
