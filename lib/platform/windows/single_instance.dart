import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 单实例保护（无原生代码，跨平台可用）。
///
/// 判定主实例用**文件独占锁**，不再靠「端口能不能绑定」：
///   - 用 `RandomAccessFile.lock(FileLock.exclusive)` 锁一个固定路径的锁文件；
///   - 锁由操作系统持有，进程崩溃时自动释放，不会留下"假死锁"；
///   - 第二个进程加锁会直接抛异常 → 确认已有实例，与端口是否被别的程序占用无关。
///
/// 唤醒已有窗口用 UDP（回环）：第二个进程发 `_activate`，主实例收到后把窗口
/// 唤到前台。**激活失败也照样退出**——单实例优先于"能不能唤出窗口"。
///
/// v1.0.16 修复：之前只靠 UDP 端口判定，端口被其他程序占用时会误判为主实例；
/// 已有实例尚未开始监听时（冷启动竞态）也会重复拉起第二个窗口。
class SingleInstance {
  const SingleInstance._();

  static const _port = 47655;
  static const _ping = 'openlist-ping';
  static const _pong = 'openlist-pong';
  static const _activate = 'openlist-show';

  /// 主实例的监听 socket（保持引用，避免被 GC 回收导致端口释放）。
  static RawDatagramSocket? _socket;

  /// 锁文件句柄：必须一直持有，进程退出时由系统释放。
  static RandomAccessFile? _lockHandle;

  /// 当前进程是否已持有单实例锁。
  static bool get isPrimary => _lockHandle != null;

  /// 成为主实例。返回 false 表示已有实例在运行。
  static Future<bool> becomePrimary({void Function()? onActivate}) async {
    // 1) 抢锁：抢不到就说明已有实例，立刻返回
    if (!await _acquireLock()) return false;

    // 2) 开 UDP 监听（只用于唤醒）。端口被占用不影响单实例语义。
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, _port);
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        switch (text) {
          case _ping:
            socket.send(utf8.encode(_pong), datagram.address, datagram.port);
            break;
          case _activate:
            socket.send(utf8.encode(_pong), datagram.address, datagram.port);
            onActivate?.call();
            break;
        }
      });
    } on SocketException {
      // 端口被别的程序占了：单实例仍由文件锁保证，只是唤醒通道不可用
    }
    return true;
  }

  /// 尝试独占锁。返回 false 只代表「锁被别人持有」。
  static Future<bool> _acquireLock() async {
    for (final path in _lockCandidates()) {
      RandomAccessFile? raf;
      try {
        final file = File(path);
        await file.parent.create(recursive: true);
        raf = await file.open(mode: FileMode.write);
      } catch (_) {
        // 目录不可写 / 文件打不开：换下一个候选路径
        continue;
      }
      try {
        await raf.lock(FileLock.exclusive);
      } catch (_) {
        // 加锁失败 = 已有实例持锁，直接判定非主实例（不要再去试别的路径）
        await raf.close();
        return false;
      }
      _lockHandle = raf;
      return true;
    }
    // 所有候选路径都不可用：宁可放行也不让应用完全打不开
    return true;
  }

  static List<String> _lockCandidates() {
    final paths = <String>[];
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty) {
        paths.add('$local${Platform.pathSeparator}OpenListClient${Platform.pathSeparator}instance.lock');
      }
    }
    paths.add('${Directory.systemTemp.path}${Platform.pathSeparator}openlist-client-instance.lock');
    return paths;
  }

  /// 已有实例在跑吗？有则要求它显示窗口并返回 true。
  ///
  /// 重发三次：主实例可能正处于启动期（Flutter 引擎初始化中），
  /// 第一次包未必来得及处理。
  static Future<bool> activateExisting({
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (await _pingOnce(timeout)) return true;
    }
    return false;
  }

  static Future<bool> _pingOnce(Duration timeout) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<bool>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        if (text == _pong && !completer.isCompleted) completer.complete(true);
      });
      socket.send(utf8.encode(_activate), InternetAddress.loopbackIPv4, _port);
      final handshake = await completer.future.timeout(timeout, onTimeout: () => false);
      await subscription.cancel();
      return handshake;
    } catch (_) {
      return false;
    } finally {
      socket?.close();
    }
  }
}
