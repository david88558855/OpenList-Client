import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
///
/// 09 已知问题：
///   - K-01 图标资源必须是 .ico。tray_manager 在 Windows 上走
///     `LoadImage(..., IMAGE_ICON, ..., LR_LOADFROMFILE)`，PNG 会加载失败并
///     留下空白占位图标，四种状态全部不可见。
///   - K-02 退出必须单次、幂等、按序释放（prefs → 单实例锁 → NIM_DELETE →
///     exit），且托盘菜单回调不能被处理两次。
enum TrayIconState { idle, transferring, error, paused }

class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  ProviderContainer? _container;
  bool _ready = false;
  bool _quitting = false;
  TrayIconState _state = TrayIconState.idle;
  ProviderSubscription<TransfersState>? _subscription;
  _OlWindowListener? _windowListener;
  DateTime? _lastLeftClick;

  bool get isQuitting => _quitting;

  Future<void> attach(ProviderContainer container) async {
    if (_ready) return;
    _container = container;
    trayManager.addListener(this);
    _windowListener = _OlWindowListener(this);
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
    _ready = false;
  }

  TrayIconState _deriveState(TransfersState state) {
    if (state.failed.isNotEmpty) return TrayIconState.error;
    if (state.active.isNotEmpty) return TrayIconState.transferring;
    if (state.paused.isNotEmpty) return TrayIconState.paused;
    return TrayIconState.idle;
  }

  /// Windows 通知区域只认 ICO/BMP；PNG 会得到 NULL HICON（K-01 根因）。
  String _iconAsset(TrayIconState state) {
    final ext = Platform.isWindows ? 'ico' : 'png';
    return 'assets/tray/tray_${state.name}.$ext';
  }

  Future<void> _applyIcon(TrayIconState state) async {
    _state = state;
    // 图标在主 isolate ready 之后创建；失败重试，避免 Explorer 尚未就绪时
    // 留下空白占位（K-01 修复方向 ②）。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await trayManager.setIcon(_iconAsset(state));
        await trayManager.setToolTip(_tooltip(state));
        return;
      } catch (error) {
        if (attempt >= 2) {
          debugPrint('tray: setIcon failed ($error)');
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
      }
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
    if (_quitting) return;
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  /// 唯一退出入口：串行、幂等、单次执行（K-02）。
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;

    // 1. 断开数据订阅，避免退出过程中还有 UI 回调
    try {
      await _subscription?.close();
      _subscription = null;
    } catch (_) {}

    // 2. 关闭窗口拦截必须先关掉，否则 close/destroy 会被 hide 吃掉
    try {
      await windowManager.setPreventClose(false).timeout(const Duration(milliseconds: 500));
    } catch (_) {}

    // 3. 移除托盘图标（NIM_DELETE），避免残留占位
    try {
      await trayManager.destroy().timeout(const Duration(milliseconds: 800));
    } catch (_) {}

    // 4. 释放窗口与单实例锁，最后进程退出
    try {
      await windowManager.destroy().timeout(const Duration(milliseconds: 800));
    } catch (_) {}

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
    // tray_manager 0.2.x 的 Windows 插件已经在 _methodCallHandler 里调用过
    // menuItem.onClick，这里再调一次会让「退出」执行两遍（K-02 直接原因之一）。
    // 保持空实现，动作统一由 MenuItem.onClick 驱动。
  }
}

/// Small bridge so tray menu entries can drive the router.
final trayNavigateProvider = StateProvider<String?>((ref) => null);

/// 关闭窗口一律收进托盘；只有托盘菜单「退出」会结束进程。
class _OlWindowListener extends WindowListener {
  final TrayService service;
  _OlWindowListener(this.service);

  @override
  void onWindowClose() async {
    if (service.isQuitting) return;
    await windowManager.hide();
  }
}
