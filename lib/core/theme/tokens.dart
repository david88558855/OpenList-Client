import 'package:flutter/material.dart';

/// Design tokens — a direct Dart mapping of the CSS custom properties in
/// OpenList-Client-Design.html v1.3 (:root block).
class OlTokens {
  const OlTokens._();

  // Brand
  static const sky = Color(0xFF38BDF8);
  static const sky600 = Color(0xFF0EA5E9);
  static const sky700 = Color(0xFF0284C7);
  static const teal = Color(0xFF2DD4BF);
  static const teal600 = Color(0xFF14B8A6);
  static const violet = Color(0xFF7C5CFC);

  // Semantic
  static const ok = Color(0xFF22C55E);
  static const okDeep = Color(0xFF0B7A63);
  static const warn = Color(0xFFF59E0B);
  static const warnDeep = Color(0xFFB47405);
  static const danger = Color(0xFFF43F5E);
  static const dangerDeep = Color(0xFFD92D4B);

  // Radii
  static const r1 = 22.0;
  static const r2 = 16.0;
  static const r3 = 12.0;
  static const r4 = 9.0;

  static const gradientPrimary = LinearGradient(
    begin: Alignment(-0.9, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF38BDF8), Color(0xFF20C6C8)],
  );

  static const gradientBrand = LinearGradient(
    begin: Alignment(-0.8, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF38BDF8), Color(0xFF2DD4BF)],
  );

  static const gradientAccentText = LinearGradient(
    begin: Alignment(-1, -0.4),
    end: Alignment(1, 0.4),
    colors: [Color(0xFF7DD3FC), Color(0xFF5EEAD4)],
  );

  static const deepPanel = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.9, 1),
    colors: [Color(0xFF0E2233), Color(0xFF123042)],
  );
}

/// Theme-aware palette. Every surface used by a screen comes from here so the
/// W7 dark variant is a palette swap, not a second layout.
class OlPalette {
  final bool isDark;
  final Color bg;
  final Color card;
  final Color surface; // sidebars
  final Color surfaceAlt; // detail panels / status bars
  final Color line;
  final Color line2;
  final Color hairline;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color nav;
  final Color navIcon;
  final Color navOnBg;
  final Color navOn;
  final Color navBadgeBg;
  final Color tableHeadBg;
  final Color th;
  final Color rowHover;
  final Color rowSel;
  final Color fieldBg;
  final Color fieldBorder;
  final Color chipBg;
  final Color chipBorder;
  final Color divider;

  const OlPalette({
    required this.isDark,
    required this.bg,
    required this.card,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.line2,
    required this.hairline,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.nav,
    required this.navIcon,
    required this.navOnBg,
    required this.navOn,
    required this.navBadgeBg,
    required this.tableHeadBg,
    required this.th,
    required this.rowHover,
    required this.rowSel,
    required this.fieldBg,
    required this.fieldBorder,
    required this.chipBg,
    required this.chipBorder,
    required this.divider,
  });

  static const light = OlPalette(
    isDark: false,
    bg: Color(0xFFEDF2F8),
    card: Color(0xFFFFFFFF),
    surface: Color(0xFFF8FAFD),
    surfaceAlt: Color(0xFFFCFDFF),
    line: Color(0xFFE3EBF3),
    line2: Color(0xFFEEF3F8),
    hairline: Color(0xFFF0F4F9),
    ink: Color(0xFF0D1B2A),
    ink2: Color(0xFF41546A),
    ink3: Color(0xFF7C8FA3),
    ink4: Color(0xFF9AABBC),
    nav: Color(0xFF50647A),
    navIcon: Color(0xFF8195A9),
    navOnBg: Color(0xFFE6F6FE),
    navOn: Color(0xFF075E7E),
    navBadgeBg: Color(0xFFEDF3F9),
    tableHeadBg: Color(0xFFFCFDFE),
    th: Color(0xFF9EAFC0),
    rowHover: Color(0xFFFAFDFF),
    rowSel: Color(0xFFF3FAFF),
    fieldBg: Color(0xFFFCFDFF),
    fieldBorder: Color(0xFFDFE9F3),
    chipBg: Color(0xFFF3F8FC),
    chipBorder: Color(0xFFE7EEF6),
    divider: Color(0xFFF4F7FA),
  );

  static const dark = OlPalette(
    isDark: true,
    bg: Color(0xFF0B1622),
    card: Color(0xFF0D1A29),
    surface: Color(0xFF091320),
    surfaceAlt: Color(0xFF0A1624),
    line: Color(0xFF182838),
    line2: Color(0xFF1A2A3C),
    hairline: Color(0xFF142435),
    ink: Color(0xFFD7E4EF),
    ink2: Color(0xFFA9BDCE),
    ink3: Color(0xFF7890A6),
    ink4: Color(0xFF5E7488),
    nav: Color(0xFF93A9BD),
    navIcon: Color(0xFF6B8298),
    navOnBg: Color(0x2438BDF8),
    navOn: Color(0xFF7DD3FC),
    navBadgeBg: Color(0xFF14243A),
    tableHeadBg: Color(0xFF0F1D2C),
    th: Color(0xFF5E7488),
    rowHover: Color(0xFF102132),
    rowSel: Color(0xFF11283A),
    fieldBg: Color(0xFF101F31),
    fieldBorder: Color(0xFF1C2E43),
    chipBg: Color(0xFF101F31),
    chipBorder: Color(0xFF1C2E43),
    divider: Color(0xFF142435),
  );
}

extension OlThemeContext on BuildContext {
  OlPalette get ol => Theme.of(this).brightness == Brightness.dark
      ? OlPalette.dark
      : OlPalette.light;
  bool get isNarrow => MediaQuery.sizeOf(this).width < 900;
}

/// Text styles. Sizes and weights are lifted from the design's CSS.
class OlText {
  const OlText._();

  static const base = TextStyle(fontSize: 13, height: 1.25);
  static const h1 = TextStyle(fontSize: 41, height: 1.06, letterSpacing: -1.8, fontWeight: FontWeight.w800);
  static const h2 = TextStyle(fontSize: 26, height: 1.15, letterSpacing: -0.8, fontWeight: FontWeight.w800);
  static const h3 = TextStyle(fontSize: 19, height: 1.2, letterSpacing: -0.5, fontWeight: FontWeight.w800);
  static const section = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: -0.15);
  static const label = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.0);
  static const eyebrow = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2.0);
  static const body = TextStyle(fontSize: 12, height: 1.7);
  static const small = TextStyle(fontSize: 10.5, height: 1.6);
  static const tiny = TextStyle(fontSize: 9, height: 1.5);
  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 0.2);
}
