import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';

/// Drag-and-drop zone + file picker for loading source images.
class ImageDropZone extends StatelessWidget {
  final String? filePath;
  final void Function(String filePath)? onFileLoaded;
  final bool enabled;

  const ImageDropZone({
    super.key,
    this.filePath,
    this.onFileLoaded,
    this.enabled = true,
  });

  static const _supportedExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.webp'};

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      onFileLoaded?.call(result.files.single.path!);
    }
  }

  void _handleDrop(DropDoneDetails details) {
    if (!enabled) return;
    final file = details.files.firstWhereOrNull(
      (f) => _supportedExtensions.contains(f.path.split('.').last.toLowerCase()),
    );
    if (file != null) {
      onFileLoaded?.call(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasFile = filePath != null;

    return DropTarget(
      onDragDone: _handleDrop,
      onDragEntered: (_) {},
      onDragExited: (_) {},
      child: GestureDetector(
        onTap: enabled ? _pickFile : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 220,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFile ? cs.primary : cs.outlineVariant,
              width: hasFile ? 2 : 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: hasFile ? _buildPreview(cs) : _buildPlaceholder(cs),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('拖放图片到此处', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('或点击选择文件 (PNG/JPEG/BMP/WebP)',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorScheme cs) {
    final fileName = filePath!.split('/').last;
    final fileSize = File(filePath!).lengthSync();
    final sizeStr = fileSize > 1024 * 1024
        ? '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(fileSize / 1024).toStringAsFixed(0)} KB';

    return Stack(
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(filePath!),
              fit: BoxFit.contain,
              height: 200,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48),
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$fileName  $sizeStr',
                style: TextStyle(fontSize: 11, color: cs.onSurface)),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
