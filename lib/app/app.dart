import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../platform/windows/tray.dart';
import 'providers.dart';
import 'router.dart';

class OpenListApp extends ConsumerWidget {
  const OpenListApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(appSettingsProvider);
    ref.listen<String?>(trayNavigateProvider, (previous, next) {
      if (next == null) return;
      router.go(next);
      ref.read(trayNavigateProvider.notifier).state = null;
    });
    return MaterialApp.router(
      title: 'OpenList Client',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: olTheme(Brightness.light),
      darkTheme: olTheme(Brightness.dark),
      themeMode: settings.themeMode,
      scrollBehavior: const _OlScrollBehavior(),
      builder: (context, child) {
        // 系统栏透明 + 图标亮度跟随主题；页面自己画到屏幕边缘，不再出现
        // 状态栏/导航栏的系统底色带（浅色主题下的“白条”就是它）。
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: olSystemBars(dark: dark),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _OlScrollBehavior extends MaterialScrollBehavior {
  const _OlScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return Scrollbar(
      controller: details.controller,
      thickness: 6,
      radius: const Radius.circular(99),
      child: child,
    );
  }
}

/// Shared page scaffold: card background, no app bar, safe areas handled.
class OlPageScaffold extends StatelessWidget {
  final Widget child;
  final Color? background;

  const OlPageScaffold({super.key, required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background ?? context.ol.card,
      body: child,
    );
  }
}

/// Full-bleed dark surface used by the player and mobile login.
class OlDarkScaffold extends StatelessWidget {
  final Widget child;
  const OlDarkScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07101B),
      body: child,
    );
  }
}

/// 1px hairline that collapses in dark mode exactly like the design.
class OlHairline extends StatelessWidget {
  final bool horizontal;
  const OlHairline({super.key, this.horizontal = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: horizontal ? double.infinity : 1,
      height: horizontal ? 1 : double.infinity,
      color: context.ol.line2,
    );
  }
}
