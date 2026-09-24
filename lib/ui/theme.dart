import 'package:flutter/material.dart';

/// Design tokens from the Beldex browser extension (public/panel.html,
/// privacy-token-integration branch) — the beldex.io look.
class BeldexColors {
  static const bg = Color(0xFF0A0A0A); // --bg
  static const panel = Color(0xFF101010); // --panel (modals)
  static const border = Color(0xFF222222); // --border
  static const rowBorder = Color(0xFF191919); // list separators
  static const input = Color(0xFF0D0D0D); // inputs, address pills
  static const hover = Color(0x0F3EC745); // rgba(62,199,69,0.06)
  static const skeletonA = Color(0xFF161616);
  static const skeletonB = Color(0xFF242424);
  static const green = Color(0xFF3EC745); // --green, from the BDX logo
  static const blue = Color(0xFF1574AD); // --blue, from the BDX logo
  static const text = Color(0xFFF2F2F2); // --text
  static const muted = Color(0xFF8A8A8A); // --text-dim
  static const faint = Color(0xFF555555); // placeholders
  static const red = Color(0xFFFF5C5C); // --red
  static const amber = Color(0xFFF5A623); // .warn / pending
  static const netAmber = Color(0xFFE8A33D); // non-mainnet badge

  // Aliases used by the feature pages
  static const card = panel;
  static const cardHigh = Color(0xFF161616);
  static const borderStrong = Color(0xFF333333);
  static const surface = panel;
  static const surfaceHigh = cardHigh;
  static const navy = bg;
  static const greenBright = green;
  static const greenDeep = Color(0xFF2E9A34);
  static const negative = red;
  static const warning = amber;
}

/// Brand fonts (bundled, OFL): Michroma for display, Space Mono for text.
class BeldexFonts {
  static const display = 'Michroma';
  static const mono = 'SpaceMono';
}

const _sharp = RoundedRectangleBorder(); // the extension uses square corners

ThemeData buildTheme({bool dark = true}) {
  const scheme = ColorScheme.dark(
    primary: BeldexColors.green,
    onPrimary: Colors.black,
    secondary: BeldexColors.blue,
    onSecondary: Colors.white,
    surface: BeldexColors.panel,
    onSurface: BeldexColors.text,
    surfaceContainerHighest: BeldexColors.cardHigh,
    surfaceContainerHigh: BeldexColors.cardHigh,
    surfaceContainer: BeldexColors.panel,
    error: BeldexColors.red,
    outline: BeldexColors.border,
    outlineVariant: BeldexColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    fontFamily: BeldexFonts.mono,
    // System fonts cover scripts Space Mono lacks (e.g. Cyrillic)
    fontFamilyFallback: const ['Noto Sans', 'DejaVu Sans', 'Liberation Sans', 'sans-serif'],
    scaffoldBackgroundColor: BeldexColors.bg,
    canvasColor: BeldexColors.bg,
    splashFactory: NoSplash.splashFactory,
    hoverColor: BeldexColors.hover,
    focusColor: BeldexColors.hover,
    highlightColor: Colors.transparent,
  );
  final text = base.textTheme.apply(bodyColor: BeldexColors.text, displayColor: BeldexColors.text);

  // White primary button that turns green on hover (extension .btn-primary)
  final primaryStyle = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return const Color(0x66FFFFFF);
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return BeldexColors.green;
      return Colors.white;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? const Color(0x99000000) : Colors.black,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    minimumSize: const WidgetStatePropertyAll(Size(110, 46)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: BeldexFonts.mono, fontWeight: FontWeight.w700, fontSize: 13.5),
    ),
    shape: const WidgetStatePropertyAll(_sharp),
    elevation: const WidgetStatePropertyAll(0),
  );

  // Ghost button: transparent with a hairline border (extension .btn-ghost)
  final ghostStyle = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? BeldexColors.faint : BeldexColors.text,
    ),
    side: WidgetStateProperty.resolveWith(
      (s) => BorderSide(
        color: s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
            ? BeldexColors.muted
            : BeldexColors.border,
      ),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    minimumSize: const WidgetStatePropertyAll(Size(110, 46)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: BeldexFonts.mono, fontWeight: FontWeight.w700, fontSize: 13.5),
    ),
    shape: const WidgetStatePropertyAll(_sharp),
  );

  OutlineInputBorder field(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: c),
  );

  return base.copyWith(
    textTheme: text.copyWith(
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 14),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13.5),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: BeldexColors.muted),
      labelLarge: text.labelLarge?.copyWith(fontSize: 13.5),
      titleMedium: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 13, letterSpacing: 1),
      titleLarge: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 16, letterSpacing: 1),
      headlineSmall: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 18, letterSpacing: 1),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BeldexColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontFamily: BeldexFonts.display, fontSize: 15, letterSpacing: 1),
    ),
    cardTheme: const CardThemeData(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: _sharp,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: BeldexColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
      titleTextStyle: TextStyle(fontFamily: BeldexFonts.display, fontSize: 15, letterSpacing: 1),
      barrierColor: Color(0xBF000000),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BeldexColors.input,
      hintStyle: const TextStyle(color: BeldexColors.faint, fontSize: 13.5),
      labelStyle: const TextStyle(color: BeldexColors.muted),
      helperStyle: const TextStyle(color: BeldexColors.muted, fontSize: 12),
      errorStyle: const TextStyle(color: BeldexColors.red, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: field(BeldexColors.border),
      enabledBorder: field(BeldexColors.border),
      disabledBorder: field(BeldexColors.rowBorder),
      focusedBorder: field(BeldexColors.green),
      errorBorder: field(BeldexColors.red),
      focusedErrorBorder: field(BeldexColors.red),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primaryStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primaryStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ghostStyle),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BeldexColors.green,
        overlayColor: Colors.transparent,
        shape: _sharp,
        textStyle: const TextStyle(fontFamily: BeldexFonts.mono, fontSize: 13),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: BeldexColors.muted,
        shape: _sharp,
        highlightColor: Colors.transparent,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: BeldexColors.text,
      unselectedLabelColor: BeldexColors.muted,
      indicatorColor: BeldexColors.green,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: BeldexColors.border,
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      labelStyle: TextStyle(fontFamily: BeldexFonts.mono, fontWeight: FontWeight.w700, fontSize: 13),
      unselectedLabelStyle: TextStyle(fontFamily: BeldexFonts.mono, fontWeight: FontWeight.w700, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(_sharp),
        side: const WidgetStatePropertyAll(BorderSide(color: BeldexColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.black : BeldexColors.text,
        ),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: BeldexFonts.mono, fontSize: 12.5)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: Colors.transparent,
      side: BorderSide(color: BeldexColors.border),
      labelStyle: TextStyle(fontFamily: BeldexFonts.mono, fontSize: 12, color: BeldexColors.text),
      shape: _sharp,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BeldexColors.green : BeldexColors.muted,
      ),
      trackColor: const WidgetStatePropertyAll(Color(0xFF1C1C1C)),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BeldexColors.green : BeldexColors.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: _sharp,
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BeldexColors.green : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.black),
      side: const BorderSide(color: BeldexColors.muted),
    ),
    radioTheme: const RadioThemeData(fillColor: WidgetStatePropertyAll(BeldexColors.green)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BeldexColors.green,
      linearTrackColor: Color(0xFF1C1C1C),
    ),
    dividerTheme: const DividerThemeData(color: BeldexColors.border, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: BeldexColors.muted, shape: _sharp),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: _sharp,
      collapsedShape: _sharp,
      iconColor: BeldexColors.muted,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: BeldexColors.panel,
      shape: RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
      textStyle: TextStyle(fontFamily: BeldexFonts.mono, fontSize: 13, color: BeldexColors.text),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(BeldexColors.panel)),
    ),
    datePickerTheme: const DatePickerThemeData(backgroundColor: BeldexColors.panel, shape: _sharp),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BeldexColors.panel,
      contentTextStyle: TextStyle(fontFamily: BeldexFonts.mono, color: BeldexColors.text, fontSize: 13),
      shape: RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
      width: 480,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: BeldexColors.panel,
        border: Border.fromBorderSide(BorderSide(color: BeldexColors.border)),
      ),
      textStyle: TextStyle(fontFamily: BeldexFonts.mono, fontSize: 12, color: BeldexColors.text),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Color(0xFF2A2A2A)),
      thickness: WidgetStatePropertyAll(4),
      radius: Radius.zero,
    ),
  );
}
