import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_converter.dart';

/// Preview panel showing original image + converted 3-color preview.
class PreviewPanel extends StatelessWidget {
  final String? sourcePath;
  final Uint8List? previewPng;
  final ConversionMode mode;
  final void Function(ConversionMode mode)? onModeChanged;
  final VoidCallback? onConvert;
  final bool converting;

  const PreviewPanel({
    super.key,
    this.sourcePath,
    this.previewPng,
    required this.mode,
    this.onModeChanged,
    this.onConvert,
    this.converting = false,
  });

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
                Icon(Icons.preview, color: cs.primary),
                const SizedBox(width: 8),
                Text('预览', style: theme.textTheme.titleSmall),
                const Spacer(),
                // Mode toggle
                SegmentedButton<ConversionMode>(
                  segments: const [
                    ButtonSegment(value: ConversionMode.nearest, label: Text('最近色')),
                    ButtonSegment(value: ConversionMode.floydSteinberg, label: Text('FS 抖动')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => onModeChanged?.call(s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: (converting || sourcePath == null) ? null : onConvert,
                  icon: converting
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(converting ? '转换中...' : '转换预览'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Side-by-side: original + preview
            Expanded(
              child: Row(
                children: [
                  // Original
                  Expanded(
                    child: _buildImageBox(
                      cs: cs,
                      label: '原图',
                      child: sourcePath != null
                          ? Image.file(
                              File(sourcePath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image, size: 32),
                            )
                          : Icon(Icons.image_outlined,
                              size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Converted
                  Expanded(
                    child: _buildImageBox(
                      cs: cs,
                      label: '墨水屏预览 (400×300)',
                      borderColor: previewPng != null ? cs.primary : null,
                      child: previewPng != null
                          ? Image.memory(
                              previewPng!,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.none, // pixel-perfect
                            )
                          : Icon(Icons.auto_fix_high_outlined,
                              size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageBox({
    required ColorScheme cs,
    required String label,
    Color? borderColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? cs.outlineVariant,
          width: borderColor != null ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Text(label, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.all(4), child: child)),
        ],
      ),
    );
  }
}
