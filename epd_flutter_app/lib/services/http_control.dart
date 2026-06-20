import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device_status.dart';
import '../models/text_command.dart';

/// HTTP client for EPD device control on port 80.
class HttpControl {
  final String _base;

  HttpControl({required String host}) : _base = 'http://$host';

  /// Fetch device status from GET /api/wifi.
  Future<DeviceStatus> getStatus() async {
    final resp = await http.get(Uri.parse('$_base/api/wifi'))
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('Status request failed: ${resp.statusCode}');
    }
    return DeviceStatus.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Trigger screen refresh: POST /display/refresh.
  Future<void> refresh() async {
    await _post('/display/refresh');
  }

  /// Clear screen (all white): POST /display/clear.
  Future<void> clear() async {
    await _post('/display/clear');
  }

  /// Put display to sleep: POST /display/sleep.
  Future<void> sleep() async {
    await _post('/display/sleep');
  }

  /// Draw text on the framebuffer: POST /display/text.
  Future<void> drawText(TextCommand cmd) async {
    final resp = await http.post(
      Uri.parse('$_base/display/text'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(cmd.toJson()),
    ).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('Text request failed: ${resp.statusCode}');
    }
  }

  Future<void> _post(String path) async {
    final resp = await http
        .post(Uri.parse('$_base$path'))
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('POST $path failed: ${resp.statusCode}');
    }
  }
}
