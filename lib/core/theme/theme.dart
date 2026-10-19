import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData olTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? OlPalette.dark : OlPalette.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: OlTokens.sky600,
    brightness: brightness,
  ).copyWith(
    surface: p.card,
    primary: OlTokens.sky600,
    error: OlTokens.danger,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.card,
    canvasColor: p.card,
    splashFactory: InkRipple.splashFactory,
    dividerColor: p.line2,
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
      fontFamilyFallback: const ['Segoe UI', 'PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC'],
    ).copyWith(
      bodyMedium: TextStyle(fontSize: 13, height: 1.25, color: p.ink, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(fontSize: 11.5, height: 1.4, color: p.ink2),
      labelLarge: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
      hintStyle: TextStyle(fontSize: 11.5, color: p.ink4, fontWeight: FontWeight.w500),
    ),
  );
}
