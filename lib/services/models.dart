/// Data models for wallet-rpc results.

class Transfer {
  Transfer(this.raw);
  final Map<String, dynamic> raw;

  String get txid => raw['txid'] as String? ?? '';
  String get type => raw['type'] as String? ?? '';
  int get amount => (raw['amount'] as num?)?.toInt() ?? 0;
  int get fee => (raw['fee'] as num?)?.toInt() ?? 0;
  int get height => (raw['height'] as num?)?.toInt() ?? 0;
  int get timestamp => (raw['timestamp'] as num?)?.toInt() ?? 0;
  int get confirmations => (raw['confirmations'] as num?)?.toInt() ?? 0;
  int get unlockTime => (raw['unlock_time'] as num?)?.toInt() ?? 0;
  String get note => raw['note'] as String? ?? '';
  String get address => raw['address'] as String? ?? '';
  String get paymentId => raw['payment_id'] as String? ?? '';
  bool get doubleSpendSeen => raw['double_spend_seen'] == true;
  int get subaddrMinor => ((raw['subaddr_index'] as Map?)?['minor'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get destinations =>
      ((raw['destinations'] as List?) ?? const []).cast<Map<String, dynamic>>();

  bool get isPending => height == 0 || const {'pending', 'pool', 'failed'}.contains(type);
  bool get isIncoming => const {'in', 'pool', 'miner', 'mnode', 'gov', 'bns'}.contains(type);
  bool get isOutgoing => const {'out', 'pending', 'stake'}.contains(type);

  /// Identity used to merge incremental fetches.
  String get key => '$txid:$type:$subaddrMinor:$amount:$height';

  Transfer withNote(String note) => Transfer({...raw, 'note': note});
}

class SubAddress {
  SubAddress(this.raw);
  final Map<String, dynamic> raw;
  String get address => raw['address'] as String? ?? '';
  int get index => (raw['address_index'] as num?)?.toInt() ?? 0;
  bool get used => raw['used'] == true;
  String get label => raw['label'] as String? ?? '';
  int? get balance => (raw['balance'] as num?)?.toInt();
  int? get unlockedBalance => (raw['unlocked_balance'] as num?)?.toInt();
  int? get unspentOutputs => (raw['num_unspent_outputs'] as num?)?.toInt();
}

class AddressBookEntry {
  AddressBookEntry({
    required this.index,
    required this.address,
    required this.name,
    required this.description,
    required this.starred,
  });

  final int index;
  final String address;
  final String name;
  final String description;
  final bool starred;

  /// The Electron wallet stores `starred::name::description` in the RPC's
  /// single description field; keep the same encoding for compatibility.
  factory AddressBookEntry.fromRpc(Map<String, dynamic> e) {
    final parts = (e['description'] as String? ?? '').split('::');
    final index = (e['index'] as num?)?.toInt() ?? 0;
    final address = e['address'] as String? ?? '';
    if (parts.length == 3) {
      return AddressBookEntry(
        index: index,
        address: address,
        starred: parts[0] == 'starred',
        name: parts[1],
        description: parts[2],
      );
    }
    if (parts.length == 2) {
      return AddressBookEntry(index: index, address: address, starred: false, name: parts[0], description: parts[1]);
    }
    return AddressBookEntry(index: index, address: address, starred: false, name: parts[0], description: '');
  }

  static String encodeDescription(String name, String description, bool starred) =>
      [if (starred) 'starred', name, description].join('::');
}

class WalletFileInfo {
  WalletFileInfo({required this.name, this.address, this.passwordProtected});
  final String name;
  final String? address;
  final bool? passwordProtected;
}

class LegacyWallet {
  LegacyWallet(this.path, this.address);
  final String path;
  final String address;
}

class WalletList {
  WalletList({this.wallets = const [], this.oldGuiDirectories = const [], this.legacy = const []});
  final List<WalletFileInfo> wallets;
  final List<String> oldGuiDirectories;
  final List<LegacyWallet> legacy;
}

class WalletSecrets {
  WalletSecrets({this.mnemonic = '', this.spendKey = '', this.viewKey = ''});
  final String mnemonic;
  final String spendKey;
  final String viewKey;
}

/// A transfer prepared with do_not_relay, waiting for user confirmation.
class PendingTransfer {
  PendingTransfer({
    required this.metadata,
    required this.amounts,
    required this.fees,
    required this.destination,
    required this.priority,
    required this.isSweepAll,
  });
  final List<String> metadata;
  final List<int> amounts;
  final List<int> fees;
  final String destination;
  final int priority;
  final bool isSweepAll;

  int get totalAmount => amounts.fold(0, (a, b) => a + b);
  int get totalFee => fees.fold(0, (a, b) => a + b);

  /// Priority 1 is "slow"; everything else is a flash transaction.
  bool get isFlash => priority != 1;
}

class BnsRecord {
  BnsRecord(this.raw);
  final Map<String, dynamic> raw;
  String get nameHash => raw['name_hash'] as String? ?? '';
  String? get name => raw['name'] as String?;
  String get owner => raw['owner'] as String? ?? '';
  String get backupOwner => raw['backup_owner'] as String? ?? '';
  int get updateHeight => (raw['update_height'] as num?)?.toInt() ?? 0;
  int? get expirationHeight => (raw['expiration_height'] as num?)?.toInt();
  String get valueWallet => raw['value_wallet'] as String? ?? '';
  String get valueBchat => raw['value_bchat'] as String? ?? '';
  String get valueBelnet => raw['value_belnet'] as String? ?? '';
  String get valueEth => raw['value_eth_addr'] as String? ?? '';
  bool get isLocked => name == null || name!.isEmpty;
}

/// Error carrying either an i18n key or a raw message for the UI.
class WalletException implements Exception {
  WalletException.i18n(String this.i18nKey, [this.args = const {}]) : message = null;
  WalletException.message(String this.message) : i18nKey = null, args = const {};
  final String? i18nKey;
  final String? message;
  final Map<String, Object?> args;

  @override
  String toString() => message ?? i18nKey ?? 'WalletException';
}
