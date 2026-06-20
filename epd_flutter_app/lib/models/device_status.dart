/// ESP8266 device status, parsed from GET /api/wifi JSON response.
class DeviceStatus {
  final String ssid;
  final String ip;
  final int rssi;
  final String mac;
  final int freeHeap;
  final int uptime;

  const DeviceStatus({
    required this.ssid,
    required this.ip,
    required this.rssi,
    required this.mac,
    required this.freeHeap,
    required this.uptime,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      ssid: json['ssid'] as String? ?? '?',
      ip: json['ip'] as String? ?? '?',
      rssi: json['rssi'] as int? ?? 0,
      mac: json['mac'] as String? ?? '?',
      freeHeap: json['freeHeap'] as int? ?? 0,
      uptime: json['uptime'] as int? ?? 0,
    );
  }

  String get uptimeFormatted {
    final h = uptime ~/ 3600;
    final m = (uptime % 3600) ~/ 60;
    final s = uptime % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }
}
