import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    // v2.6：桌面端不用 Material 3 默认的 Zoom 转场——切页面时整页「放大又缩小」
    // 在 1440×900 的窗口里非常刺眼。桌面统一改成淡入，Android 保留系统手感。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      },
    ),
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

/// 系统栏样式：状态栏与导航栏都透明，让页面/导航条自身的底色一直铺到屏幕边缘。
/// 图标亮度跟随主题——深色界面用浅色图标，浅色界面用深色图标。
/// 安卓 15 起强制 edge-to-edge，statusBarColor / systemNavigationBarColor 会被忽略，
/// 但旧版本系统与桌面平台仍依赖这里的取值，所以三端共用同一套定义。
SystemUiOverlayStyle olSystemBars({required bool dark}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 恒定深色页面（登录、播放器）使用：系统栏图标始终为浅色。
const SystemUiOverlayStyle olDarkSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarBrightness: Brightness.dark,
  statusBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);
