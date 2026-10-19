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
  bool _windowReady = false;
  bool _pendingShow = false;
  TrayIconState _state = TrayIconState.idle;
  ProviderSubscription<TransfersState>? _subscription;
  _OlWindowListener? _windowListener;
  DateTime? _lastLeftClick;
  Timer? _watchdog;

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
    _startWatchdog();
  }

  /// Explorer 重启后任务栏重建，`Shell_NotifyIcon` 注册的图标会被清掉，
  /// 而 tray_manager 0.2.x 不监听 `TaskbarCreated`（插件里没有这段代码），
  /// 图标就永久消失、右键菜单也弹不出来（v2.3 修复 P2-16）。
  ///
  /// 兜底做法：每 25s 查一次图标在通知区域的矩形。拿不到（或被
  /// `getBounds` 返回 0 尺寸）说明注册已失效，于是 `destroy()` 把插件的
  /// `tray_icon_setted` 复位，再 `setIcon` 走一次 `NIM_ADD` 重新挂上。
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 25), (_) => _ensureIconAlive());
  }

  Future<void> _ensureIconAlive() async {
    if (!_ready || _quitting) return;
    var alive = false;
    try {
      final bounds = await trayManager.getBounds();
      // 图标真的在通知区域时宽高必然大于 0；Explorer 重启后这里会是 0 或 null。
      alive = bounds != null && bounds.width > 0 && bounds.height > 0;
    } catch (_) {
      alive = false;
    }
    if (alive) return;
    debugPrint('tray: icon missing (Explorer restarted?), re-adding');
    await _recreateIcon();
  }

  /// 重新注册托盘图标与菜单（NIM_DELETE → NIM_ADD）。
  Future<void> _recreateIcon() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    await _applyIcon(_state);
    await _rebuildMenu();
  }

  Future<void> dispose() async {
    _watchdog?.cancel();
    _watchdog = null;
    _subscription?.close();
    _subscription = null;
    if (_windowListener != null) {
      windowManager.removeListener(_windowListener!);
      _windowListener = null;
    }
    trayManager.removeListener(this);
    _ready = false;
    _windowReady = false;
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
        MenuItem(key: 'show', label: '显示主界面', onClick: (item) => showMainWindow()),
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

  /// 主实例就绪前收到的「显示」请求先暂存，等托盘/窗口 ready 后再执行。
  void requestShow() {
    if (!_windowReady) {
      _pendingShow = true;
      return;
    }
    showMainWindow();
  }

  void markWindowReady() {
    _windowReady = true;
    if (_pendingShow) {
      _pendingShow = false;
      showMainWindow();
    }
  }

  /// 把主窗口唤到前台（v2.1 修复：托盘「显示主界面」无响应）。
  ///
  /// 从托盘唤回时窗口可能处于 隐藏 / 最小化 / 被其他窗口遮挡 三种状态，
  /// 单独 show() 在 Windows 前台锁下不会真正置前，因此按序恢复、置顶再取消。
  Future<void> showMainWindow() async {
    if (_quitting) return;
    try {
      if (!await windowManager.isVisible()) await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.focus();
    } catch (error) {
      debugPrint('tray: showMainWindow failed ($error)');
    }
  }

  /// 唯一退出入口：串行、幂等、单次执行（K-02）。
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    _watchdog?.cancel();
    _watchdog = null;

    // 1. 断开数据订阅，避免退出过程中还有 UI 回调（close() 是同步 void）
    try {
      _subscription?.close();
      _subscription = null;
    } catch (_) {}

    // 2. 偏好落盘（便携版 userdata/prefs.json），避免退出时丢最后一次写入
    try {
      await _container?.read(prefsProvider).flush().timeout(const Duration(milliseconds: 800));
    } catch (_) {}

    // 3. 关闭窗口拦截必须先关掉，否则 close/destroy 会被 hide 吃掉
    try {
      await windowManager.setPreventClose(false).timeout(const Duration(milliseconds: 500));
    } catch (_) {}

    // 4. 移除托盘图标（NIM_DELETE），避免残留占位
    try {
      await trayManager.destroy().timeout(const Duration(milliseconds: 800));
    } catch (_) {}

    // 5. 释放窗口与单实例锁，最后进程退出
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
      showMainWindow();
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
