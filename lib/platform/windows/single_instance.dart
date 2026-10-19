import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Windows 单实例保护（无原生代码）。
///
/// 机制：第一个进程在回环地址上绑定固定 UDP 端口并应答心跳；第二个进程
/// 启动时先尝试绑定，失败则发 `ping`，收到 `pong` 说明已有实例 →
/// 通知它对端把窗口唤到前台，然后自己 `exit(0)`，不创建第二个窗口。
///
/// v2.1 修复点：
///   - 只有「ping 有应答」才判定为已有实例，避免端口被其他程序占用时误判；
///   - 激活回调统一走 TrayService.showMainWindow（含 restore / 置顶 / 聚焦）；
///   - 主实例尚未就绪时，激活请求会被暂存，窗口就绪后立即执行。
class SingleInstance {
  const SingleInstance._();

  static const _port = 47655;
  static const _ping = 'openlist-ping';
  static const _pong = 'openlist-pong';
  static const _activate = 'openlist-show';

  static RawDatagramSocket? _socket;

  /// 成为主实例：绑定端口并监听激活/心跳请求。
  static Future<bool> becomePrimary({void Function()? onActivate}) async {
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
      return true;
    } on SocketException {
      return false;
    }
  }

  /// 已有实例在跑吗？有则要求它显示窗口并返回 true。
  static Future<bool> activateExisting({
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
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
