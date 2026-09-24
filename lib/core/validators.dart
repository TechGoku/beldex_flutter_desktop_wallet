// Field validators, ported from the Electron wallet's validators/common.js.

bool isHex64(String input) => RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(input);

bool isPrivateKey(String input) => input.isEmpty || isHex64(input);

bool isMasterNodeKey(String input) => input.length == 64 && RegExp(r'^[0-9A-Za-z]+$').hasMatch(input);

bool isBchatId(String input) => input.length == 66 && RegExp(r'^bd[0-9A-Za-z]+$').hasMatch(input);

bool isBelnetAddress(String input) =>
    input.length == 52 && RegExp(r'^[ybndrfg8ejkmcpqxot1uwisza345h769]{51}[yo]$').hasMatch(input);

bool isEthAddress(String input) => RegExp(r'^(0x)?[0-9a-fA-F]{40}$').hasMatch(input);

/// Name part of a BNS name (without `.bdx`).
bool isBnsName(String input) {
  final value = input.toLowerCase();
  if (value.isEmpty) return false;
  final maxLength = value.contains('-') ? 63 : 32;
  if (value.length > maxLength) return false;
  if (value.startsWith('-') || value.endsWith('-')) return false;
  return RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(value);
}

bool isBchatOrBelnetName(String input) {
  final value = input.toLowerCase();
  final name = value.endsWith('.bdx') ? value.substring(0, value.length - 4) : value;
  return isBnsName(name) || RegExp(r'^[a-z0-9_]([a-z0-9-_]*[a-z0-9_])?$').hasMatch(value);
}

/// Quick local check before asking wallet-rpc: standard, sub- and
/// integrated addresses are 95-106 base58 characters.
bool looksLikeAddress(String input) =>
    input.length >= 95 && input.length <= 106 && RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(input);

bool isBnsAddressName(String input) => input.toLowerCase().endsWith('.bdx');

int seedWordCount(String seed) => seed.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

bool isValidSeedLength(String seed) => const {14, 24, 25, 26}.contains(seedWordCount(seed));
