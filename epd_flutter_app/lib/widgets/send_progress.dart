import 'package:flutter/material.dart';

/// Send progress bar + action buttons + log output.
class SendProgress extends StatelessWidget {
  final bool sending;
  final int step;          // 0..5 (0=idle, 5=done)
  final List<String> log;
  final VoidCallback? onSend;
  final VoidCallback? onClear;
  final VoidCallback? onSleep;
  final bool canSend;

  const SendProgress({
    super.key,
    this.sending = false,
    this.step = 0,
    this.log = const [],
    this.onSend,
    this.onClear,
    this.onSleep,
    this.canSend = false,
  });

  static const _stepLabels = [
    '等待发送',
    '1/5 黑色层上半...',
    '2/5 黑色层下半...',
    '3/5 红色层上半...',
    '4/5 红色层下半...',
    '5/5 刷新显示 ✓',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.send, color: cs.primary),
                const SizedBox(width: 8),
                Text('发送', style: theme.textTheme.titleSmall),
                const Spacer(),
                // Action buttons
                TextButton.icon(
                  onPressed: canSend && !sending ? onClear : null,
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: const Text('清屏'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: canSend && !sending ? onSleep : null,
                  icon: const Icon(Icons.bedtime, size: 16),
                  label: const Text('休眠'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: canSend && !sending ? onSend : null,
                  icon: sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload, size: 16),
                  label: Text(sending ? '发送中...' : '发送到设备'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: step / 5.0,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _stepLabels[step.clamp(0, 5)],
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            // Log output
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    log.isEmpty ? '日志输出...' : log.join('\n'),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
