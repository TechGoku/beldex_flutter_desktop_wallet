import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Languages shipped with the app. The JSON files in assets/i18n are
/// converted 1:1 from the Electron wallet's translations, so keys match.
class Language {
  const Language(this.code, this.name, this.flag);
  final String code;
  final String name;
  final String flag;
}

const languages = <Language>[
  Language('en-us', 'English', '🇬🇧'),
  Language('ru', 'Русский', '🇷🇺'),
  Language('de', 'Deutsch', '🇩🇪'),
  Language('fr', 'Français', '🇫🇷'),
  Language('es', 'Español', '🇪🇸'),
  Language('pt-br', 'Português', '🇧🇷'),
];

/// Minimal vue-i18n compatible translator: flat dotted keys, `{name}`
/// placeholders and `a | b | c` pluralisation.
class I18n extends ChangeNotifier {
  I18n._();
  static final I18n instance = I18n._();

  /// Strings the Flutter app needs that the Electron translations lack.
  static const _extras = {'dialog.confirmTransaction.confirm': 'Confirm', 'footer.daemon': 'Daemon'};

  Map<String, String> _fallback = const {};
  Map<String, String> _messages = const {};
  String _locale = 'en-us';

  String get locale => _locale;

  Future<void> load(String locale) async {
    if (_fallback.isEmpty) {
      _fallback = await _read('en-us');
    }
    if (!languages.any((l) => l.code == locale)) locale = 'en-us';
    _messages = locale == 'en-us' ? _fallback : await _read(locale);
    _locale = locale;
    notifyListeners();
  }

  Future<Map<String, String>> _read(String locale) async {
    final raw = await rootBundle.loadString('assets/i18n/$locale.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }

  /// Translate [key]. Unknown keys are returned as-is, like vue-i18n.
  String t(String key, [Map<String, Object?> args = const {}]) {
    final template = _messages[key] ?? _fallback[key] ?? _extras[key] ?? key;
    return _interpolate(template.split('|').first.trim(), args);
  }

  /// Pluralised translation: picks the `|`-separated variant for [count].
  String tc(String key, int count, [Map<String, Object?> args = const {}]) {
    final template = _messages[key] ?? _fallback[key] ?? key;
    final variants = template.split('|').map((s) => s.trim()).toList();
    String chosen;
    if (variants.length == 1) {
      chosen = variants[0];
    } else if (variants.length == 2) {
      chosen = count == 1 ? variants[0] : variants[1];
    } else {
      chosen = variants[count.clamp(0, variants.length - 1)];
    }
    return _interpolate(chosen, {'count': count, 'n': count, ...args});
  }

  String _interpolate(String template, Map<String, Object?> args) {
    if (args.isEmpty || !template.contains('{')) return template;
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final value = args[m.group(1)];
      return value == null ? m.group(0)! : value.toString();
    });
  }
}

/// Shorthand used throughout the UI.
String t(String key, [Map<String, Object?> args = const {}]) => I18n.instance.t(key, args);
