import 'dart:typed_data';

/// Result of converting a source image to the e-paper 3-color format.
///
/// Contains the four 7500-byte half-screen chunks ready for TCP transmission,
/// plus a PNG-encoded preview for UI display.
class ConvertedImage {
  /// Black layer, rows 0–149 (7500 bytes, 1bpp MSB-first).
  final Uint8List blackTop;

  /// Black layer, rows 150–299 (7500 bytes).
  final Uint8List blackBottom;

  /// Red layer, rows 0–149 (7500 bytes).
  final Uint8List redTop;

  /// Red layer, rows 150–299 (7500 bytes).
  final Uint8List redBottom;

  /// PNG-encoded preview image (400×300, 3-color rendering).
  final Uint8List previewPng;

  const ConvertedImage({
    required this.blackTop,
    required this.blackBottom,
    required this.redTop,
    required this.redBottom,
    required this.previewPng,
  });
}
