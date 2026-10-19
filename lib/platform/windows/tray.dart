import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/providers.dart';
import '../../features/transfers/transfers_controller.dart';

/// W9 — Windows tray: four icon states, left click opens, right click menu,
/// closing the window hides to tray, only “退出” ends the process.
enum TrayIconState { idle, transferring, error, paused }

class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  ProviderContainer? _container;
  bool _ready = false;
  TrayIconState _state = TrayIconState.idle;
  ProviderSubscription<TransfersState>? _subscription;
  _OlWindowListener? _windowListener;

  Future<void> attach(ProviderContainer container) async {
    if (_ready) return;
    _container = container;
    trayManager.addListener(this);
    _windowListener = _OlWindowListener(container);
    windowManager.addListener(_windowListener!);
    await _applyIcon(TrayIconState.idle);
    await _rebuildMenu();
    _subscription = container.listen<TransfersState>(transfersProvider, (previous, next) {
      final state = _deriveState(next);
      if (state != _state) {
        _applyIcon(state);
      }
      _rebuildMenu();
    });
    _ready = true;
  }

  Future<void> dispose() async {
    _subscription?.close();
    _subscription = null;
    if (_windowListener != null) {
      windowManager.removeListener(_windowListener!);
      _windowListener = null;
    }
    trayManager.removeListener(this);
  }

  TrayIconState _deriveState(TransfersState state) {
    if (state.failed.isNotEmpty) return TrayIconState.error;
    if (state.active.isNotEmpty) return TrayIconState.transferring;
    if (state.paused.isNotEmpty) return TrayIconState.paused;
    return TrayIconState.idle;
  }

  Future<void> _applyIcon(TrayIconState state) async {
    _state = state;
    try {
      // tray_manager resolves the icon relative to data/flutter_assets on
      // Windows, which is exactly where Flutter copies assets/tray/*.
      await trayManager.setIcon('assets/tray/tray_${state.name}.png');
      await trayManager.setToolTip(_tooltip(state));
    } catch (_) {
      // A missing tray (rare Windows shells) must never crash the app.
    }
  }

  String _tooltip(TrayIconState state) {
    final transfers = _container?.read(transfersProvider);
    switch (state) {
      case TrayIconState.transferring:
        return 'OpenList · 传输中 ${transfers?.active.length ?? 0}';
      case TrayIconState.error:
        return 'OpenList · ${transfers?.failed.length ?? 0} 个任务失败';
      case TrayIconState.paused:
        return 'OpenList · 已暂停';
      case TrayIconState.idle:
        return 'OpenList Client';
    }
  }

  Future<void> _rebuildMenu() async {
    final container = _container;
    if (container == null) return;
    final servers = container.read(serverListProvider);
    final transfers = container.read(transfersProvider);
    final menu = Menu(
      items: [
        MenuItem(key: 'open', label: '打开 OpenList', onClick: (item) => _showWindow()),
        MenuItem.separator(),
        MenuItem.submenu(
          key: 'servers',
          label: '服务器',
          submenu: Menu(
            items: [
              for (final server in servers.servers)
                MenuItem.checkbox(
                  key: 'srv_${server.id}',
                  label: server.name,
                  checked: server.id == servers.activeId,
                  onClick: (item) async {
                    await container.read(sessionProvider.notifier).switchTo(server.id);
                    await container.read(filesProvider.notifier).attach();
                    await _showWindow();
                  },
                ),
              MenuItem.separator(),
              MenuItem(
                key: 'manage',
                label: '管理服务器…',
                onClick: (item) {
                  _showWindow();
                  container.read(trayNavigateProvider.notifier).state = '/servers';
                },
              ),
            ],
          ),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'pause',
          label: transfers.pausedGlobally ? '继续全部传输' : '暂停全部传输',
          onClick: (item) async {
            final notifier = container.read(transfersProvider.notifier);
            if (transfers.pausedGlobally) {
              await notifier.resumeAll();
            } else {
              await notifier.pauseAll();
            }
          },
        ),
        MenuItem(
          key: 'transfers',
          label: '传输中心',
          onClick: (item) {
            _showWindow();
            container.read(trayNavigateProvider.notifier).state = '/transfers';
          },
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出', onClick: (item) => _quit()),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    menuItem.onClick?.call(menuItem);
  }
}

/// Small bridge so tray menu entries can drive the router.
final trayNavigateProvider = StateProvider<String?>((ref) => null);

class _OlWindowListener extends WindowListener {
  final ProviderContainer container;

  _OlWindowListener(this.container);

  @override
  void onWindowClose() async {
    final closeToTray = container.read(appSettingsProvider).closeToTray;
    if (closeToTray) {
      await windowManager.hide();
    } else {
      await trayManager.destroy();
      exit(0);
    }
  }
}
