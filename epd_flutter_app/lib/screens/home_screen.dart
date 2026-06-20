import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/device_status.dart';
import '../models/converted_image.dart';
import '../services/http_control.dart';
import '../services/tcp_image_sender.dart';
import '../services/image_converter.dart';
import '../widgets/device_toolbar.dart';
import '../widgets/image_drop_zone.dart';
import '../widgets/preview_panel.dart';
import '../widgets/send_progress.dart';

const _epdWidth = 400;
const _epdHeight = 300;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Connection state
  String _host = '';
  HttpControl? _http;
  TcpImageSender? _tcp;
  DeviceStatus? _status;
  bool _connected = false;

  // Image state
  String? _sourcePath;
  ConvertedImage? _convertedImage;
  ConversionMode _mode = ConversionMode.floydSteinberg;
  bool _converting = false;

  // Send state
  bool _sending = false;
  int _sendStep = 0;
  final List<String> _log = [];

  final _converter = ImageConverter();

  void _logMessage(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _log.add('[$ts] $msg'));
  }

  // ---- Connection ----

  Future<void> _connect(String host) async {
    setState(() {
      _host = host;
      _http = HttpControl(host: host);
      _tcp = TcpImageSender(host: host);
      _status = null;
      _connected = false;
    });

    try {
      final status = await _http!.getStatus();
      setState(() {
        _status = status;
        _connected = true;
      });
      _logMessage('已连接: ${status.ssid} @ ${status.ip}');
    } catch (e) {
      _logMessage('连接失败: $e');
      setState(() => _connected = false);
    }
  }

  // ---- File loading ----

  void _onFileLoaded(String path) {
    setState(() {
      _sourcePath = path;
      _convertedImage = null; // invalidate old conversion
    });
    _logMessage('加载图片: ${path.split('/').last}');
  }

  // ---- Conversion ----

  Future<void> _convert() async {
    if (_sourcePath == null) return;

    setState(() => _converting = true);
    _logMessage('开始转换 ($_mode)...');

    try {
      final converted = await _converter.convert(
        _sourcePath!,
        mode: _mode,
      );
      setState(() {
        _convertedImage = converted;
        _converting = false;
      });
      // Log pixel statistics for debugging
      final blackPixels = _countColoredPixels(converted.blackTop) +
          _countColoredPixels(converted.blackBottom);
      final redPixels = _countColoredPixels(converted.redTop) +
          _countColoredPixels(converted.redBottom);
      final total = _epdWidth * _epdHeight;
      _logMessage('转换完成 ✓ 黑色: $blackPixels/$total'
          ' (${(blackPixels * 100 / total).toStringAsFixed(1)}%)'
          ' 红色: $redPixels/$total'
          ' (${(redPixels * 100 / total).toStringAsFixed(1)}%)');
    } catch (e) {
      _logMessage('转换失败: $e');
      setState(() => _converting = false);
    }
  }

  // ---- Send ----

  Future<void> _sendToDevice() async {
    if (_convertedImage == null || _tcp == null || !_connected) return;

    setState(() {
      _sending = true;
      _sendStep = 0;
    });

    try {
      setState(() => _sendStep = 1);
      _logMessage('发送黑色层上半...');
      _logMessage('  B-Top hex: ${_hex8(_convertedImage!.blackTop)}');
      await _tcp!.sendBlackTop(_convertedImage!.blackTop);

      setState(() => _sendStep = 2);
      _logMessage('发送黑色层下半...');
      await _tcp!.sendBlackBottom(_convertedImage!.blackBottom);

      setState(() => _sendStep = 3);
      _logMessage('发送红色层上半...');
      _logMessage('  R-Top hex: ${_hex8(_convertedImage!.redTop)}');
      await _tcp!.sendRedTop(_convertedImage!.redTop);

      setState(() => _sendStep = 4);
      _logMessage('发送红色层下半...');
      await _tcp!.sendRedBottom(_convertedImage!.redBottom);

      setState(() => _sendStep = 5);
      _logMessage('刷新显示...');
      await _tcp!.sendRefresh();

      _logMessage('全部完成 ✓ (约需 15 秒刷新)');
    } catch (e) {
      _logMessage('发送失败: $e');
    }

    setState(() => _sending = false);
  }

  Future<void> _clearDevice() async {
    if (_http == null || !_connected) return;
    try {
      _logMessage('清屏...');
      await _http!.clear();
      _logMessage('已清屏 ✓');
    } catch (e) {
      _logMessage('清屏失败: $e');
    }
  }

  Future<void> _sleepDevice() async {
    if (_http == null || !_connected) return;
    try {
      _logMessage('屏幕休眠...');
      await _http!.sleep();
      _logMessage('已休眠 ✓');
    } catch (e) {
      _logMessage('休眠失败: $e');
    }
  }

  /// Built-in checkerboard test pattern — verifies TCP path independently.
  void _testCheckerboard() {
    final converted = ImageConverter.generateCheckerboard();
    setState(() {
      _convertedImage = converted;
      _sourcePath = null;
    });
    final bp = _countColoredPixels(converted.blackTop) +
        _countColoredPixels(converted.blackBottom);
    _logMessage('棋盘格测试图案已生成 ✓ 黑色像素: $bp/${_epdWidth * _epdHeight}');
    _logMessage('  B-Top hex: ${_hex8(converted.blackTop)}');
  }

  /// Hex dump first 8 bytes of a buffer for debugging.
  String _hex8(Uint8List data) {
    return data.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Count bits set to 0 (colored pixels) in a 1bpp buffer.
  int _countColoredPixels(Uint8List buffer) {
    int count = 0;
    for (final byte in buffer) {
      var b = byte;
      b = (b & 0x55) + ((b >> 1) & 0x55);
      b = (b & 0x33) + ((b >> 2) & 0x33);
      b = (b & 0x0F) + ((b >> 4) & 0x0F);
      count += 8 - b;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EPD 4.2" 墨水屏上位机'),
        centerTitle: true,
        actions: [
          if (_connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.circle, size: 10, color: Colors.green),
                label: Text(_host, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Top: Device toolbar
          DeviceToolbar(
            onConnected: _connect,
            httpControl: _http,
            status: _status,
            connected: _connected,
          ),
          // Middle: Drop zone + Preview + Send
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel: Drop zone
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ImageDropZone(
                          filePath: _sourcePath,
                          onFileLoaded: _onFileLoaded,
                          enabled: !_sending,
                        ),
                      ),
                      // Send progress
                      Expanded(
                        child: SendProgress(
                          sending: _sending,
                          step: _sendStep,
                          log: _log,
                          onSend: _sendToDevice,
                          onClear: _clearDevice,
                          onSleep: _sleepDevice,
                          onTestPattern: _testCheckerboard,
                          canSend: _convertedImage != null && _connected,
                          canClear: _connected,
                          canSleep: _connected,
                          canTest: _connected,
                        ),
                      ),
                    ],
                  ),
                ),
                // Right panel: Preview
                Expanded(
                  flex: 5,
                  child: PreviewPanel(
                    sourcePath: _sourcePath,
                    previewPng: _convertedImage?.previewPng,
                    mode: _mode,
                    onModeChanged: (m) {
                      setState(() {
                        _mode = m;
                        _convertedImage = null; // reconvert needed
                      });
                    },
                    onConvert: _convert,
                    converting: _converting,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
