import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/converted_image.dart';

/// E-paper display dimensions.
const epdWidth = 400;
const epdHeight = 300;
const widthBytes = epdWidth ~/ 8; // 50
const halfHeight = epdHeight ~/ 2; // 150
const halfSize = widthBytes * halfHeight; // 7500

/// Color conversion mode for the 3-color e-paper.
enum ConversionMode {
  /// Simple nearest-color matching (fast, good for icons / solid colors).
  nearest,

  /// Floyd-Steinberg error-diffusion dithering (best for photos).
  floydSteinberg,
}

/// Three possible output colors for the e-paper.
enum _Label { black, white, red }

/// Converts arbitrary images to the EPD 4.2" tri-color bitmap format.
class ImageConverter {
  /// Load an image from file, convert to e-paper format.
  Future<ConvertedImage> convert(
    String filePath, {
    ConversionMode mode = ConversionMode.floydSteinberg,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final source = img.decodeImage(bytes);
    if (source == null) {
      throw Exception('无法解码图片: $filePath');
    }

    // Resize to 400×300 with Lanczos interpolation.
    final resized = img.copyResize(
      source,
      width: epdWidth,
      height: epdHeight,
      interpolation: img.Interpolation.average,
    );

    // Build black & red full-frame buffers (all white = 0xFF).
    final blackFull = Uint8List(epdWidth * epdHeight ~/ 8);
    final redFull = Uint8List(epdWidth * epdHeight ~/ 8);
    _fillWhite(blackFull);
    _fillWhite(redFull);

    // Build 3-color preview image.
    final preview = img.Image(width: epdWidth, height: epdHeight);

    if (mode == ConversionMode.floydSteinberg) {
      _floydSteinberg(resized, blackFull, redFull, preview);
    } else {
      _nearestColor(resized, blackFull, redFull, preview);
    }

    // Split full buffers into top/bottom halves.
    return ConvertedImage(
      blackTop: _extractHalf(blackFull, 0),
      blackBottom: _extractHalf(blackFull, halfSize),
      redTop: _extractHalf(redFull, 0),
      redBottom: _extractHalf(redFull, halfSize),
      previewPng: Uint8List.fromList(img.encodePng(preview)),
    );
  }

  // ---- Algorithm: Nearest-color matching ----

  void _nearestColor(
    img.Image src,
    Uint8List blackBuf,
    Uint8List redBuf,
    img.Image preview,
  ) {
    for (int y = 0; y < epdHeight; y++) {
      for (int x = 0; x < epdWidth; x++) {
        final p = src.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final label = _classify(r, g, b);
        _writePixel(blackBuf, redBuf, x, y, label);
        _drawPreview(preview, x, y, label);
      }
    }
  }

  // ---- Algorithm: Floyd-Steinberg dithering ----

  void _floydSteinberg(
    img.Image src,
    Uint8List blackBuf,
    Uint8List redBuf,
    img.Image preview,
  ) {
    // Floating-point error buffers.
    final errR = List.generate(epdHeight + 1, (_) => Float64List(epdWidth + 1));
    final errG = List.generate(epdHeight + 1, (_) => Float64List(epdWidth + 1));
    final errB = List.generate(epdHeight + 1, (_) => Float64List(epdWidth + 1));

    for (int y = 0; y < epdHeight; y++) {
      for (int x = 0; x < epdWidth; x++) {
        final p = src.getPixel(x, y);
        double cr = p.r.toDouble() + errR[y][x];
        double cg = p.g.toDouble() + errG[y][x];
        double cb = p.b.toDouble() + errB[y][x];

        // Clamp to [0, 255].
        cr = cr.clamp(0, 255);
        cg = cg.clamp(0, 255);
        cb = cb.clamp(0, 255);

        final label = _classify(cr.round(), cg.round(), cb.round());
        final (qr, qg, qb) = _paletteRgb(label);

        // Compute error.
        final eR = cr - qr;
        final eG = cg - qg;
        final eB = cb - qb;

        // Distribute error (Floyd-Steinberg weights).
        _addError(errR, x + 1, y, eR * 7 / 16);
        _addError(errR, x - 1, y + 1, eR * 3 / 16);
        _addError(errR, x, y + 1, eR * 5 / 16);
        _addError(errR, x + 1, y + 1, eR * 1 / 16);

        _addError(errG, x + 1, y, eG * 7 / 16);
        _addError(errG, x - 1, y + 1, eG * 3 / 16);
        _addError(errG, x, y + 1, eG * 5 / 16);
        _addError(errG, x + 1, y + 1, eG * 1 / 16);

        _addError(errB, x + 1, y, eB * 7 / 16);
        _addError(errB, x - 1, y + 1, eB * 3 / 16);
        _addError(errB, x, y + 1, eB * 5 / 16);
        _addError(errB, x + 1, y + 1, eB * 1 / 16);

        _writePixel(blackBuf, redBuf, x, y, label);
        _drawPreview(preview, x, y, label);
      }
    }
  }

  // ---- Helpers ----

  /// Add error to a pixel, bounds-checked.
  void _addError(List<Float64List> buf, int x, int y, double val) {
    if (x >= 0 && x < epdWidth && y < epdHeight) {
      buf[y][x] += val;
    }
  }

  /// Three possible output colors for the e-paper.

  /// Classify an RGB value into one of the 3 e-paper colors.
  _Label _classify(int r, int g, int b) {
    // Euclidean distance to palette colors.
    final dBlack = r * r + g * g + b * b;                      // to (0,0,0)
    final dWhite = (255 - r) * (255 - r) + (255 - g) * (255 - g) + (255 - b) * (255 - b); // to (255,255,255)
    final dRed = (255 - r) * (255 - r) + g * g + b * b;        // to (255,0,0)

    if (dBlack <= dWhite && dBlack <= dRed) return _Label.black;
    if (dRed <= dWhite) return _Label.red;
    return _Label.white;
  }

  /// Returns the (R, G, B) of the quantized palette color.
  (int, int, int) _paletteRgb(_Label label) {
    return switch (label) {
      _Label.black => (0, 0, 0),
      _Label.white => (255, 255, 255),
      _Label.red   => (255, 0, 0),
    };
  }

  /// Write one pixel into the 1bpp black & red buffers.
  ///
  /// Bit encoding (MSB first):
  ///   pixel(x,y) = byte[x/8 + y*50], bit[7 - x%8]
  ///   bit=1 → white (inactive), bit=0 → layer color (black/red)
  ///
  /// Layer semantics:
  ///   black=0, red=1 → BLACK pixel
  ///   black=1, red=0 → RED pixel
  ///   black=1, red=1 → WHITE pixel
  void _writePixel(
    Uint8List blackBuf,
    Uint8List redBuf,
    int x,
    int y,
    _Label label,
  ) {
    final byteIdx = y * widthBytes + x ~/ 8;
    final bitIdx = 7 - (x % 8);
    final mask = 1 << bitIdx;

    switch (label) {
      case _Label.black:
        blackBuf[byteIdx] &= ~mask; // clear bit = 0
        // red stays 1 (white in red layer)
        break;
      case _Label.red:
        redBuf[byteIdx] &= ~mask; // clear bit = 0
        // black stays 1 (white in black layer)
        break;
      case _Label.white:
        // Both stay 1 (both layers white = display white)
        break;
    }
  }

  void _drawPreview(img.Image preview, int x, int y, _Label label) {
    switch (label) {
      case _Label.black:
        preview.setPixelRgba(x, y, 0, 0, 0, 255);
      case _Label.white:
        preview.setPixelRgba(x, y, 255, 255, 255, 255);
      case _Label.red:
        preview.setPixelRgba(x, y, 255, 0, 0, 255);
    }
  }

  void _fillWhite(Uint8List buf) {
    for (int i = 0; i < buf.length; i++) {
      buf[i] = 0xFF;
    }
  }

  Uint8List _extractHalf(Uint8List full, int offset) {
    return Uint8List.fromList(full.sublist(offset, offset + halfSize));
  }

  /// Generate a checkerboard test pattern (matches Python test_epd.py make_checker).
  /// Black checkerboard on black layer, all white on red layer.
  static ConvertedImage generateCheckerboard() {
    final blackFull = Uint8List(epdWidth * epdHeight ~/ 8);
    final redFull = Uint8List(epdWidth * epdHeight ~/ 8);
    _fillStatic(blackFull);
    _fillStatic(redFull);

    // Black layer: checkerboard (top half normal, bottom half inverted)
    for (int y = 0; y < epdHeight; y++) {
      final invert = y >= halfHeight;
      for (int x = 0; x < epdWidth; x++) {
        bool black = ((x ~/ 16) + (y ~/ 16)) % 2 == 0;
        if (invert) black = !black;
        if (black) {
          final byteIdx = y * widthBytes + x ~/ 8;
          final bitIdx = 7 - (x % 8);
          blackFull[byteIdx] &= ~(1 << bitIdx);
        }
      }
    }

    // Build preview
    final preview = img.Image(width: epdWidth, height: epdHeight);
    for (int y = 0; y < epdHeight; y++) {
      for (int x = 0; x < epdWidth; x++) {
        final byteIdx = y * widthBytes + x ~/ 8;
        final bitIdx = 7 - (x % 8);
        final isBlack = (blackFull[byteIdx] & (1 << bitIdx)) == 0;
        preview.setPixelRgba(x, y, isBlack ? 0 : 255, 255, 255, 255);
      }
    }

    return ConvertedImage(
      blackTop: Uint8List.fromList(blackFull.sublist(0, halfSize)),
      blackBottom: Uint8List.fromList(blackFull.sublist(halfSize, halfSize * 2)),
      redTop: Uint8List.fromList(redFull.sublist(0, halfSize)),
      redBottom: Uint8List.fromList(redFull.sublist(halfSize, halfSize * 2)),
      previewPng: Uint8List.fromList(img.encodePng(preview)),
    );
  }

  static void _fillStatic(Uint8List buf) {
    for (int i = 0; i < buf.length; i++) {
      buf[i] = 0xFF;
    }
  }
}
