import 'package:flutter/material.dart';
import '../models/device_status.dart';
import '../services/http_control.dart';
import '../services/mdns_discovery.dart';

/// Top toolbar for device IP input, connection, and mDNS discovery.
class DeviceToolbar extends StatefulWidget {
  final void Function(String host)? onConnected;
  final HttpControl? httpControl;
  final DeviceStatus? status;
  final bool connected;

  const DeviceToolbar({
    super.key,
    this.onConnected,
    this.httpControl,
    this.status,
    this.connected = false,
  });

  @override
  State<DeviceToolbar> createState() => _DeviceToolbarState();
}

class _DeviceToolbarState extends State<DeviceToolbar> {
  final _ipController = TextEditingController(text: '192.168.31.212');
  bool _scanning = false;
  List<DiscoveredDevice> _devices = [];

  Future<void> _connect() async {
    final host = _ipController.text.trim();
    if (host.isEmpty) return;
    widget.onConnected?.call(host);
  }

  Future<void> _scanMdns() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });

    final discovery = MdnsDiscovery();
    try {
      await for (final device in discovery.discover()) {
        setState(() => _devices.add(device));
        // Auto-select first device found.
        if (_devices.length == 1 && _ipController.text.isEmpty) {
          _ipController.text = device.host;
        }
      }
    } catch (_) {
      // mDNS scan timeout or error — silently ignore.
    }

    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: IP input + buttons
            Row(
              children: [
                Icon(Icons.wifi, color: widget.connected ? Colors.green : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: '设备 IP',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _connect,
                  icon: Icon(widget.connected ? Icons.refresh : Icons.play_arrow),
                  label: Text(widget.connected ? '刷新' : '连接'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _scanning ? null : _scanMdns,
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  tooltip: 'mDNS 扫描',
                ),
                const SizedBox(width: 4),
                // Connection indicator
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.connected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.connected ? '已连接' : '未连接',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const Spacer(),
                // Status summary
                if (widget.status != null)
                  Text(
                    '信号: ${widget.status!.rssi} dBm | 内存: ${widget.status!.freeHeap} B | 运行: ${widget.status!.uptimeFormatted}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
              ],
            ),
            // Row 2: mDNS results
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: _devices.map((d) => ActionChip(
                  avatar: const Icon(Icons.devices, size: 16),
                  label: Text('${d.name} (${d.host})', style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _ipController.text = d.host;
                    _connect();
                  },
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
