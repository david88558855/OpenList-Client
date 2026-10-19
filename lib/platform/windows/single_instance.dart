import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// Single instance without native code: the first process binds a loopback UDP
/// port; a second launch pokes it and exits, so the running window comes back
/// to the foreground instead of opening a duplicate.
class SingleInstance {
  static const _port = 47655;
  static const _showCommand = 'openlist-show';

  static RawDatagramSocket? _socket;

  static Future<bool> becomePrimary({void Function()? onActivate}) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, _port);
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _socket!.receive();
        if (datagram == null) return;
        if (utf8.decode(datagram.data, allowMalformed: true) == _showCommand) {
          onActivate?.call();
        }
      });
      return true;
    } on SocketException {
      return false;
    }
  }

  static Future<void> pokeExisting() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      socket.send(utf8.encode(_showCommand), InternetAddress.loopbackIPv4, _port);
      socket.close();
    } catch (_) {
      // ignore
    }
  }

  static Future<void> revealWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
