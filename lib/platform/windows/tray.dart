import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/providers.dart';
import '../../features/transfers/transfers_controller.dart';

/// W9 — Windows 托盘。
///
/// 交互约定：
///   - 启动后常驻托盘图标（四态：空闲 / 传输中 / 失败 / 暂停）；
///   - 左键双击显示主界面；
///   - 右键菜单两项：显示主界面、退出；
///   - 关闭窗口、Alt+F4、任务栏关闭一律只收进托盘，只有菜单「退出」结束进程。
enum TrayIconState { idle, transferring, error, paused }

class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  ProviderContainer? _container;
  bool _ready = false;
  TrayIconState _state = TrayIconState.idle;
  ProviderSubscription<TransfersState>? _subscription;
  _OlWindowListener? _windowListener;
  DateTime? _lastLeftClick;

  Future<void> attach(ProviderContainer container) async {
    if (_ready) return;
    _container = container;
    trayManager.addListener(this);
    _windowListener = _OlWindowListener();
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

  /// 只有两项：显示主界面 / 退出。
  Future<void> _rebuildMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示主界面', onClick: (item) => _showWindow()),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出', onClick: (item) => _quit()),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (_) {
      // 托盘不可用时忽略，主窗口行为不受影响
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.restore();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    // 左键双击才显示主界面：450ms 内的第二次按下视为双击。
    final now = DateTime.now();
    final last = _lastLeftClick;
    _lastLeftClick = now;
    if (last != null && now.difference(last) <= const Duration(milliseconds: 450)) {
      _lastLeftClick = null;
      _showWindow();
    }
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

/// 关闭窗口一律收进托盘；只有托盘菜单「退出」会结束进程。
class _OlWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }
}
