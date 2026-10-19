import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/prefs.dart';
import 'core/theme/theme.dart';
import 'platform/windows/single_instance.dart';
import 'platform/windows/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await _configureSystemBars();

  final prefs = await Prefs.load();
  final container =
      ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);

  if (Platform.isWindows) {
    // 单实例：已有实例在跑时只把它的窗口唤到前台，本进程立即退出。
    final primary = await SingleInstance.becomePrimary(
      onActivate: TrayService.instance.requestShow,
    );
    if (!primary) {
      final handedOver = await SingleInstance.activateExisting();
      if (handedOver) exit(0);
      // 端口被其他程序占用且无应答：继续启动，避免应用完全打不开。
    }
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1024, 680),
      center: true,
      title: 'OpenList Client',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
    if (Platform.isWindows) {
      await TrayService.instance.attach(container);
      TrayService.instance.markWindowReady();
    }
  }

  await container.read(sessionProvider.notifier).boot();
  await container.read(filesProvider.notifier).attach();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OpenListApp(),
    ),
  );
}

/// 全平台统一 edge-to-edge：内容自己画到状态栏/导航栏下方，再由 AppFrame 用
/// 安全区把内容让开。否则安卓 15+（targetSdk 36 强制 edge-to-edge）会出现
/// 内容压到状态栏、底部或多出一条系统底色带的问题。
Future<void> _configureSystemBars() async {
  if (!Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(olSystemBars(dark: false));
}
