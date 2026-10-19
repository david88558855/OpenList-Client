import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/prefs.dart';
import 'platform/windows/single_instance.dart';
import 'platform/windows/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await Prefs.load();
  final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);

  if (Platform.isWindows) {
    final primary = await SingleInstance.becomePrimary(onActivate: SingleInstance.revealWindow);
    if (!primary) {
      await SingleInstance.pokeExisting();
      exit(0);
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
