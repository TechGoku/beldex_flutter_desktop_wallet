import '../core/config.dart';

/// Links into explorer.beldex.io (or the testnet explorer).
Uri explorerUrl(NetType net, String kind, String id) {
  final base = net == NetType.testnet ? 'https://testnet.beldex.dev' : 'https://explorer.beldex.io';
  return Uri.parse('$base/$kind/$id');
}
