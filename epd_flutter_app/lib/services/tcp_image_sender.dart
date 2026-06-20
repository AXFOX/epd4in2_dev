import 'dart:io';
import 'package:flutter/foundation.dart';

/// TCP command bytes for the EPD image protocol (port 81).
const _cmdBlackTop = 0x00;
const _cmdBlackBottom = 0x01;
const _cmdRedTop = 0x02;
const _cmdRedBottom = 0x03;
const _cmdRefresh = 0xFF;

/// Sends raw half-screen bitmap data to ESP8266 via TCP port 81.
///
/// Each call opens a fresh TCP connection, sends 1 command byte + optional
/// 7500-byte payload, then closes. This matches the device's per-connection
/// transaction model.
class TcpImageSender {
  final String host;
  final int port;
  final Duration timeout;

  TcpImageSender({
    required this.host,
    this.port = 81,
    this.timeout = const Duration(seconds: 10),
  });

  /// Send a single command + optional data chunk.
  Future<void> _send(int cmd, [Uint8List? data]) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add([cmd]);
      if (data != null) {
        assert(data.length == 7500,
            'Half-screen chunk must be exactly 7500 bytes, got ${data.length}');
        socket.add(data);
      }
      await socket.flush();
      await socket.close();
    } catch (e) {
      socket.destroy();
      rethrow;
    }
  }

  Future<void> sendBlackTop(Uint8List data) => _send(_cmdBlackTop, data);
  Future<void> sendBlackBottom(Uint8List data) => _send(_cmdBlackBottom, data);
  Future<void> sendRedTop(Uint8List data) => _send(_cmdRedTop, data);
  Future<void> sendRedBottom(Uint8List data) => _send(_cmdRedBottom, data);
  Future<void> sendRefresh() => _send(_cmdRefresh);

  /// Send a complete converted image (all 4 half-screen chunks + refresh).
  Future<void> sendFullImage({
    required Uint8List blackTop,
    required Uint8List blackBottom,
    required Uint8List redTop,
    required Uint8List redBottom,
    bool autoRefresh = true,
    ValueChanged<String>? onProgress,
  }) async {
    onProgress?.call('发送黑色层上半...');
    await sendBlackTop(blackTop);
    onProgress?.call('发送黑色层下半...');
    await sendBlackBottom(blackBottom);
    onProgress?.call('发送红色层上半...');
    await sendRedTop(redTop);
    onProgress?.call('发送红色层下半...');
    await sendRedBottom(redBottom);
    if (autoRefresh) {
      onProgress?.call('刷新显示...');
      await sendRefresh();
    }
  }
}
