import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// TCP command bytes for the EPD image protocol (port 81).
const _cmdBlackTop = 0x00;
const _cmdBlackBottom = 0x01;
const _cmdRedTop = 0x02;
const _cmdRedBottom = 0x03;
const _cmdRefresh = 0xFF;

/// Sends raw half-screen bitmap data to ESP8266 via TCP port 81.
class TcpImageSender {
  final String host;
  final int port;
  final Duration timeout;

  TcpImageSender({
    required this.host,
    this.port = 81,
    this.timeout = const Duration(seconds: 10),
  });

  /// Send command + optional 7500-byte payload using RawSocket for
  /// reliable half-close (shutdown send) semantics.
  Future<void> _send(int cmd, [Uint8List? data]) async {
    // Build the full packet upfront
    final payloadLen = data?.length ?? 0;
    final packetLen = 1 + payloadLen;
    final packet = Uint8List(packetLen);
    packet[0] = cmd;
    if (data != null) packet.setAll(1, data);

    final socket = await RawSocket.connect(host, port, timeout: timeout);
    try {
      // Send ALL data in a loop — write() may return short
      int offset = 0;
      while (offset < packetLen) {
        final sent = socket.write(packet, offset, packetLen - offset);
        if (sent <= 0) throw SocketException('TCP write returned $sent');
        offset += sent;
      }

      // Half-close: shutdown send direction → sends FIN, flushes buffer.
      // ESP8266's readBytes() will receive all bytes then see EOF.
      socket.shutdown(SocketDirection.send);

      // Wait briefly for the FIN to propagate, then close fully.
      await Future.delayed(const Duration(milliseconds: 30));
      socket.close();
    } catch (e) {
      socket.close();
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
