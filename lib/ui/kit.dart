import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/format.dart';
import 'theme.dart';

// Components mirroring the Beldex browser extension's design system
// (public/panel.html): black dot-grid, flat sections split by hairlines,
// square corners, white primary buttons, Michroma headings, Space Mono text.

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// The beldex.io dot grid: 1px dots every 26px at 7% white.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x12FFFFFF);
    for (var y = 13.0; y < size.height; y += 26) {
      for (var x = 13.0; x < size.width; x += 26) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Scaffold with the dot-grid background.
class BScaffold extends StatelessWidget {
  const BScaffold({super.key, required this.body});
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BeldexColors.bg,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _DotGridPainter())),
        body,
      ],
    ),
  );
}

/// Centered content column (the extension's `.wrap`, widened for desktop).
class Column560 extends StatelessWidget {
  const Column560({
    super.key,
    required this.children,
    this.maxWidth = 560,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(padding: padding, children: children),
    ),
  );
}

/// Section container. Flat by default like the extension's `.card`;
/// [outlined] gives the framed `#101010` panel used for forms.
class BCard extends StatelessWidget {
  const BCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.outlined = false,
    this.color,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool outlined;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? (outlined ? BeldexColors.panel : Colors.transparent),
      shape: outlined ? const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)) : null,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop layout
// ---------------------------------------------------------------------------

/// Framed `#101010` panel with an optional small-caps title row.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: BeldexColors.panel,
    shape: const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (title ?? '').toUpperCase(),
                      style: const TextStyle(
                        fontFamily: BeldexFonts.display,
                        fontSize: 11,
                        color: BeldexColors.muted,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    ),
  );
}

/// Lays [children] out side by side (weighted by [flex]) when there is room,
/// stacked otherwise.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.flex,
    this.breakpoint = 760,
    this.gap = 16,
    this.stretch = false,
  });
  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint;
  final double gap;

  /// Equal-height columns. Children must support intrinsic sizing (no
  /// LayoutBuilder unless it sits inside a fixed-size box).
  final bool stretch;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: gap), child],
          ],
        );
      }
      final row = Row(
        crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: flex?[i] ?? 1, child: child),
          ],
        ],
      );
      return stretch ? IntrinsicHeight(child: row) : row;
    },
  );
}

/// Page title row of the desktop shell.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 18, letterSpacing: 1.2),
            ),
            if (subtitle != null) ...[const SizedBox(height: 6), Muted(subtitle!, size: 12.5)],
          ],
        ),
      ),
      for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), a],
    ],
  );
}

/// Muted uppercase column headings for table-style lists.
class TableHead extends StatelessWidget {
  const TableHead(this.text, {super.key, this.align = TextAlign.left});
  final String text;
  final TextAlign align;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: align,
    style: const TextStyle(fontSize: 11, color: BeldexColors.muted, letterSpacing: 1),
  );
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.large = false, this.badge});
  final bool large;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final logo = SvgPicture.asset('assets/images/logo.svg', width: large ? 56 : 24, height: large ? 56 : 24);
    final word = Text(
      'BELDEX',
      style: TextStyle(fontFamily: BeldexFonts.display, fontSize: large ? 20 : 13, letterSpacing: large ? 2 : 1),
    );
    final badgeWidget = badge == null
        ? null
        : Padding(padding: const EdgeInsets.only(left: 8), child: NetLabel(badge!, warn: true));
    if (large) {
      return Column(mainAxisSize: MainAxisSize.min, children: [logo, const SizedBox(height: 12), word, ?badgeWidget]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [logo, const SizedBox(width: 8), word, ?badgeWidget]);
  }
}

/// Dim uppercase section label (`.settings-section-label`); [bright] gives
/// the stronger `.detail-section-label`.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.bright = false});
  final String text;
  final Widget? trailing;
  final bool bright;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: BeldexFonts.display,
              fontSize: bright ? 12 : 10.5,
              color: bright ? BeldexColors.text : BeldexColors.muted,
              letterSpacing: 1.5,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class H2 extends StatelessWidget {
  const H2(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 15, letterSpacing: 1),
    ),
  );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 12.5, this.center = false, this.color});
  final String text;
  final double size;
  final bool center;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : null,
    style: TextStyle(color: color ?? BeldexColors.muted, fontSize: math.max(size, 11.5), height: 1.45),
  );
}

/// Network label beside the wallet name: muted on mainnet, amber elsewhere.
class NetLabel extends StatelessWidget {
  const NetLabel(this.label, {super.key, this.warn = false});
  final String label;
  final bool warn;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: warn ? BeldexColors.netAmber : BeldexColors.border),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontFamily: BeldexFonts.display,
        fontSize: 8.5,
        letterSpacing: 0.5,
        height: 1,
        color: warn ? BeldexColors.netAmber : BeldexColors.muted,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/// Back button + title (`.settings-header`); Esc also goes back.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.actions = const [],
    this.maxWidth = 560,
  });
  final String title;
  final VoidCallback onBack;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onBack},
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Row(
                    children: [
                      BackSquare(onTap: onBack),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 15, letterSpacing: 1),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 34×34 back button with a hairline border (`.settings-back`).
class BackSquare extends StatelessWidget {
  const BackSquare({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Back (Esc)',
    child: _Hoverable(
      builder: (hover) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border.all(color: hover ? BeldexColors.muted : BeldexColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.chevron_left, size: 22, color: BeldexColors.text),
        ),
      ),
    ),
  );
}

/// Underlined tab strip (`.home-tabs`).
class HomeTabs<T> extends StatelessWidget {
  const HomeTabs({super.key, required this.tabs, required this.value, required this.onChanged});
  final Map<T, String> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 18, bottom: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: BeldexColors.border)),
    ),
    child: Row(
      children: [
        for (final e in tabs.entries)
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: e.key == value ? BeldexColors.green : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: e.key == value ? BeldexColors.text : BeldexColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder});
  final Widget Function(bool hover) builder;
  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(_hover),
  );
}

/// White button that turns green on hover (`.btn-primary`).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.color,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final button = FilledButton(
      style: color == null
          ? null
          : FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: color == BeldexColors.blue ? Colors.white : Colors.black,
            ),
      onPressed: busy ? null : onPressed,
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Transparent button with a hairline border (`.btn-ghost` / `.btn-danger`).
class GhostButton extends StatelessWidget {
  const GhostButton(this.label, {super.key, this.onPressed, this.icon, this.expand = true, this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      style: danger
          ? ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.hovered) ? Colors.black : BeldexColors.red,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.hovered) ? BeldexColors.red : Colors.transparent,
              ),
              side: const WidgetStatePropertyAll(BorderSide(color: BeldexColors.red)),
            )
          : null,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Small bordered button with a green glyph (`.btn-icon`).
class IconChip extends StatelessWidget {
  const IconChip({super.key, this.icon, required this.onTap, this.tooltip, this.label, this.display = false});
  final IconData? icon;
  final VoidCallback onTap;
  final String? tooltip;
  final String? label;

  /// Label in the display font (the header wallet switcher).
  final bool display;

  @override
  Widget build(BuildContext context) {
    final body = _Hoverable(
      builder: (hover) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 11, vertical: 6),
          decoration: BoxDecoration(border: Border.all(color: hover ? BeldexColors.green : BeldexColors.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    label!,
                    overflow: TextOverflow.ellipsis,
                    style: display
                        ? const TextStyle(fontFamily: BeldexFonts.display, fontSize: 13, color: BeldexColors.green)
                        : const TextStyle(fontSize: 12.5, color: BeldexColors.green),
                  ),
                ),
                if (icon != null) const SizedBox(width: 6),
              ],
              if (icon != null) Icon(icon, size: 16, color: BeldexColors.green),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

/// Square filter chips (`.chip`).
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final e in options.entries)
        GestureDetector(
          onTap: () => onChanged(e.key),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: e.key == value ? BeldexColors.green : BeldexColors.border),
              ),
              child: Text(
                e.value,
                style: TextStyle(fontSize: 12, color: e.key == value ? BeldexColors.green : BeldexColors.muted),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Square on/off switch (`.switch`).
class SquareSwitch extends StatelessWidget {
  const SquareSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 18,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          border: Border.all(color: value ? BeldexColors.green : BeldexColors.border),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 12, height: 12, color: value ? BeldexColors.green : BeldexColors.muted),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Rows & values
// ---------------------------------------------------------------------------

/// Monospace value with a copy button that flips to a check (`.addr`).
class CopyPill extends StatefulWidget {
  const CopyPill(this.value, {super.key, this.display, this.secret = false, this.onCopied});
  final String value;
  final String? display;

  /// Secrets are cleared from the clipboard after 60 s.
  final bool secret;
  final VoidCallback? onCopied;

  @override
  State<CopyPill> createState() => _CopyPillState();
}

class _CopyPillState extends State<CopyPill> {
  bool _copied = false;

  Future<void> _copy() async {
    await copyText(widget.value, secret: widget.secret);
    widget.onCopied?.call();
    if (!mounted) return;
    setState(() => _copied = true);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(11, 2, 2, 2),
    decoration: BoxDecoration(
      color: BeldexColors.input,
      border: Border.all(color: BeldexColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Tooltip(
            message: widget.value,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              widget.display ?? shorten(widget.value, head: 14, tail: 14),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.copy_rounded, color: BeldexColors.green),
        ),
      ],
    ),
  );
}

Timer? _clipboardClear;

/// Copies [value]; secrets are wiped from the clipboard after 60 s unless
/// something else was copied meanwhile.
Future<void> copyText(String value, {bool secret = false}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!secret) return;
  _clipboardClear?.cancel();
  _clipboardClear = Timer(const Duration(seconds: 60), () async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == value) await Clipboard.setData(const ClipboardData(text: ''));
  });
}

/// Small green text link (`.ok` spans in the extension).
class TextLink extends StatelessWidget {
  const TextLink(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: BeldexColors.green)),
    ),
  );
}

/// Outlined "Copy" button that confirms with a tick.
class CopyButton extends StatefulWidget {
  const CopyButton(this.value, {super.key, this.label = 'Copy', this.secret = false});
  final String value;
  final String label;
  final bool secret;
  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GhostButton(
    _copied ? 'Copied' : widget.label,
    icon: _copied ? Icons.check : Icons.copy_rounded,
    expand: false,
    onPressed: () async {
      await copyText(widget.value, secret: widget.secret);
      if (!mounted) return;
      setState(() => _copied = true);
      _reset?.cancel();
      _reset = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _copied = false);
      });
    },
  );
}

/// Label / value row with a hairline separator (`.detail-row`).
class DetailLine extends StatelessWidget {
  const DetailLine(this.label, this.value, {super.key, this.valueColor, this.last = false});
  final String label;
  final Widget value;
  final Color? valueColor;
  final bool last;

  DetailLine.text(this.label, String text, {super.key, this.valueColor, this.last = false})
    : value = Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 13, color: valueColor),
      );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: BeldexColors.rowBorder)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted)),
        const SizedBox(width: 16),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: value),
        ),
      ],
    ),
  );
}

/// Icon + label + chevron row (`.settings-item`).
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? BeldexColors.red : BeldexColors.text;
    return InkWell(
      onTap: onTap,
      hoverColor: danger ? const Color(0x0FFF5C5C) : BeldexColors.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: danger ? BeldexColors.red : BeldexColors.muted),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13.5, color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: BeldexColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                (onTap == null
                    ? const SizedBox.shrink()
                    : const Icon(Icons.chevron_right, size: 18, color: BeldexColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Hairline between groups (`.settings-divider`).
class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1));
}

/// Small icon followed by text, in one colour (status labels).
class IconLabel extends StatelessWidget {
  const IconLabel(this.icon, this.text, {super.key, required this.color, this.size = 12});
  final IconData icon;
  final String text;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = math.max(size, 11.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: s + 1, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: s, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class Warn extends StatelessWidget {
  const Warn(this.text, {super.key, this.color = BeldexColors.amber});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.warning_amber_rounded, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 12.5, color: color, height: 1.45)),
      ),
    ],
  );
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => text == null || text!.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(text!, style: const TextStyle(color: BeldexColors.red, fontSize: 12.5)),
        );
}

// ---------------------------------------------------------------------------
// Loading & feedback
// ---------------------------------------------------------------------------

/// Shimmering placeholder (`.skel`).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.width, required this.height, this.circle = false});
  final double width;
  final double height;
  final bool circle;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle ? null : BorderRadius.circular(3),
        gradient: LinearGradient(
          begin: Alignment(-1 + _c.value * 3, 0),
          end: Alignment(_c.value * 3, 0),
          colors: const [BeldexColors.skeletonA, BeldexColors.skeletonB, BeldexColors.skeletonA],
        ),
      ),
    ),
  );
}

/// Animated success tick (`.tick`): the circle draws, then the check.
class SuccessTick extends StatefulWidget {
  const SuccessTick({super.key, this.size = 72});
  final double size;
  @override
  State<SuccessTick> createState() => _SuccessTickState();
}

class _SuccessTickState extends State<SuccessTick> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(size: Size.square(widget.size), painter: _TickPainter(_c.value)),
  );
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 52;
    final circle = Paint()
      ..color = BeldexColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s;
    final circleT = (t / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(26 * s, 26 * s), radius: 24 * s),
      -math.pi / 2,
      2 * math.pi * circleT,
      false,
      circle,
    );
    final checkT = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    if (checkT <= 0) return;
    final path = Path()
      ..moveTo(14 * s, 27 * s)
      ..lineTo(22 * s, 35 * s)
      ..lineTo(38 * s, 19 * s);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * checkT),
      Paint()
        ..color = BeldexColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}

/// Square failure mark (`.fail-mark`).
class FailMark extends StatelessWidget {
  const FailMark({super.key});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.6, end: 1),
    duration: const Duration(milliseconds: 250),
    builder: (_, v, child) => Transform.scale(scale: v, child: child),
    child: Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(border: Border.all(color: BeldexColors.red, width: 2)),
      child: const Icon(Icons.close, color: BeldexColors.red, size: 26),
    ),
  );
}

/// Thin progress bar with a green glow (`.progress`).
class GlowProgress extends StatelessWidget {
  const GlowProgress(this.value, {super.key});
  final double value;
  @override
  Widget build(BuildContext context) => Container(
    height: 3,
    color: const Color(0xFF1C1C1C),
    alignment: Alignment.centerLeft,
    child: AnimatedFractionallySizedBox(
      duration: const Duration(milliseconds: 400),
      widthFactor: value.clamp(0, 1),
      child: Container(
        decoration: const BoxDecoration(
          color: BeldexColors.green,
          boxShadow: [BoxShadow(color: BeldexColors.green, blurRadius: 8)],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

({String label, Color color, double pct})? passwordStrength(String pw) {
  if (pw.isEmpty) return null;
  var classes = 0;
  if (RegExp('[a-z]').hasMatch(pw)) classes++;
  if (RegExp('[A-Z]').hasMatch(pw)) classes++;
  if (RegExp('[0-9]').hasMatch(pw)) classes++;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(pw)) classes++;
  var score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 12) score++;
  if (pw.length >= 16) score++;
  score += classes >= 3 ? 2 : (classes >= 2 ? 1 : 0);
  if (score <= 1) return (label: 'weak', color: BeldexColors.red, pct: 0.33);
  if (score <= 3) return (label: 'fair', color: BeldexColors.amber, pct: 0.66);
  return (label: 'strong', color: BeldexColors.green, pct: 1.0);
}

class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.password, {super.key});
  final String password;
  @override
  Widget build(BuildContext context) {
    final s = passwordStrength(password);
    if (s == null) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: s.pct,
              minHeight: 3,
              color: s.color,
              backgroundColor: const Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(width: 10),
          Text(s.label, style: TextStyle(fontSize: 11.5, color: s.color)),
        ],
      ),
    );
  }
}

class Field extends StatelessWidget {
  const Field({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.obscure = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.suffix,
    this.inputFormatters,
    this.mono = false,
    this.errorText,
    this.helper,
  });
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final bool mono;
  final String? errorText;
  final String? helper;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: obscure ? 1 : maxLines,
      minLines: 1,
      inputFormatters: inputFormatters,
      cursorColor: BeldexColors.green,
      style: TextStyle(fontSize: mono ? 12.5 : 13.5),
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        suffixIcon: suffix,
        errorText: errorText,
        helperText: helper,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Modals
// ---------------------------------------------------------------------------

/// Extension-style modal: 75% black overlay, square `#101010` panel.
Future<T?> showBModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  double width = 420,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'close',
    barrierColor: const Color(0xBF000000),
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: BeldexColors.panel,
          shape: const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(ctx).height - 48),
            child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: builder(ctx)),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

String timeAgo(int unixSeconds) {
  if (unixSeconds <= 0) return '';
  final s = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)).inSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  if (s < 86400 * 30) return '${s ~/ 86400}d ago';
  return formatDate(unixSeconds);
}
