import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// TCP command bytes for the EPD image protocol (port 81).
const _cmdBlackTop = 0x00;
const _cmdBlackBottom = 0x01;
const _cmdRedTop = 0x02;
const _cmdRedBottom = 0x03;

/// Each half-screen chunk = 7500 bytes (50 bytes/row × 150 rows).
const int halfChunkSize = 7500;

/// Sends raw half-screen bitmap data to ESP8266 via TCP port 81.
///
/// Refresh is handled separately via HTTP `POST /display/refresh`
/// because `TurnOnDisplay()` blocks ~15s and would watchdog-reset
/// if called inside a TCP handler.
class TcpImageSender {
  final String host;
  final int port;
  final Duration timeout;

  TcpImageSender({
    required this.host,
    this.port = 81,
    this.timeout = const Duration(seconds: 10),
  });

  /// Send command + 7500-byte payload via TCP.
  ///
  /// ESP8266's WiFiClient::stop() does not reliably send a FIN that
  /// Dart's socket.done can detect. We use a conservative delay after
  /// flush to ensure the ESP has time to read and buffer the data.
  Future<void> _send(int cmd, Uint8List data) async {
    assert(data.length == halfChunkSize,
        'Half-screen chunk must be exactly $halfChunkSize bytes');

    final packet = Uint8List(1 + data.length);
    packet[0] = cmd;
    packet.setAll(1, data);

    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(packet);
      await socket.flush();

      // Give ESP8266 time to receive and buffer all 7500 bytes.
      // lwIP receive window ≈ 5840 bytes; data arrives in ~5 TCP segments.
      // Wait briefly, then attempt to read an optional ACK from device.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Wait for optional ACK ('OK\n') from device with a short timeout.
      try {
        final completer = Completer<List<int>>();
        final subscription = socket.listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        }, onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }, onDone: () {
          if (!completer.isCompleted) completer.complete(<int>[]);
        });
        final data = await completer.future.timeout(const Duration(seconds: 2));
        if (data.isNotEmpty) {
          if (kDebugMode) print('EPD ACK: ${String.fromCharCodes(data)}');
        }
        await subscription.cancel();
      } catch (_) {
        // ignore timeout or read errors
      }

      await socket.close();
    } catch (e) {
      try { await socket.close(); } catch (_) {}
      rethrow;
    }
  }

  Future<void> sendBlackTop(Uint8List data) => _send(_cmdBlackTop, data);
  Future<void> sendBlackBottom(Uint8List data) => _send(_cmdBlackBottom, data);
  Future<void> sendRedTop(Uint8List data) => _send(_cmdRedTop, data);
  Future<void> sendRedBottom(Uint8List data) => _send(_cmdRedBottom, data);

  /// Send a complete converted image (all 4 half-screen chunks).
  ///
  /// Refresh is NOT triggered here — call [HttpControl.refresh] separately.
  Future<void> sendFullImage({
    required Uint8List blackTop,
    required Uint8List blackBottom,
    required Uint8List redTop,
    required Uint8List redBottom,
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
  }
}
