import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image/image.dart' as img;

class ThermalRaster {
  const ThermalRaster({
    required this.widthBytes,
    required this.height,
    required this.data,
  });

  final int widthBytes;
  final int height;
  final List<int> data;
}

/// Converts images and Flutter-rendered RTL text to monochrome printer data.
class RasterPrint {
  static const int maxWidthDots = 576;
  static const int maxHeightDots = 4096;

  static ThermalRaster imageToRaster(
    List<int> encodedImage, {
    int maxWidth = maxWidthDots,
    int maxHeight = maxHeightDots,
    int threshold = 160,
    String mode = 'floydSteinberg',
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(encodedImage));
    if (decoded == null) {
      throw const FormatException('صيغة الصورة غير مدعومة أو الملف تالف');
    }
    return _decodedToRaster(
      decoded,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      threshold: threshold,
      mode: mode,
    );
  }

  static ThermalRaster _decodedToRaster(
    img.Image decoded, {
    required int maxWidth,
    required int maxHeight,
    required int threshold,
    required String mode,
  }) {
    final scale = math.min(
      1.0,
      math.min(maxWidth / decoded.width, maxHeight / decoded.height),
    );
    final width = math.max(1, (decoded.width * scale).floor()).toInt();
    final height = math.max(1, (decoded.height * scale).floor()).toInt();
    final raster = (width == decoded.width && height == decoded.height)
        ? decoded
        : img.copyResize(
            decoded,
            width: width,
            height: height,
            interpolation: img.Interpolation.average,
          );

    final bytesPerRow = (raster.width + 7) ~/ 8;
    final pixels = List<int>.filled(bytesPerRow * raster.height, 0);
    final luminance = List<double>.filled(raster.width * raster.height, 255);
    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < raster.width; x++) {
        final pixel = raster.getPixel(x, y);
        final alpha = pixel.a / 255.0;
        final red = pixel.r * alpha + 255 * (1 - alpha);
        final green = pixel.g * alpha + 255 * (1 - alpha);
        final blue = pixel.b * alpha + 255 * (1 - alpha);
        luminance[y * raster.width + x] = 0.299 * red + 0.587 * green + 0.114 * blue;
      }
    }
    const ordered = [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5],
    ];
    void setBlack(int x, int y) {
      pixels[y * bytesPerRow + (x ~/ 8)] |= 0x80 >> (x % 8);
    }
    if (mode == 'floydSteinberg' || mode == 'atkinson') {
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < raster.width; x++) {
          final index = y * raster.width + x;
          final old = luminance[index].clamp(0.0, 255.0).toDouble();
          final next = old < threshold ? 0.0 : 255.0;
          if (next == 0) setBlack(x, y);
          final error = old - next;
          if (mode == 'floydSteinberg') {
            void add(int dx, int dy, double factor) {
              final nx = x + dx, ny = y + dy;
              if (nx >= 0 && nx < raster.width && ny < raster.height) {
                luminance[ny * raster.width + nx] += error * factor;
              }
            }
            add(1, 0, 7 / 16); add(-1, 1, 3 / 16);
            add(0, 1, 5 / 16); add(1, 1, 1 / 16);
          } else {
            void add(int dx, int dy) {
              final nx = x + dx, ny = y + dy;
              if (nx >= 0 && nx < raster.width && ny < raster.height) {
                luminance[ny * raster.width + nx] += error / 8;
              }
            }
            add(1, 0); add(2, 0); add(-1, 1); add(0, 1); add(1, 1); add(0, 2);
          }
        }
      }
    } else {
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < raster.width; x++) {
          final value = luminance[y * raster.width + x];
          final cutoff = mode == 'ordered'
              ? (ordered[y % 4][x % 4] * 16 + 8).toDouble()
              : threshold.toDouble();
          if (value < cutoff) setBlack(x, y);
        }
      }
    }
    return ThermalRaster(
      widthBytes: bytesPerRow,
      height: raster.height,
      data: pixels,
    );
  }

  static Uint8List imageToPreviewPng(
    List<int> encodedImage, {
    required int maxWidth,
    required String alignment,
    String mode = 'floydSteinberg',
  }) {
    const margin = 8;
    final source = imageToRaster(
      encodedImage,
      maxWidth: maxWidth,
      mode: mode,
    );
    final raster = _positionRaster(
      source,
      paperWidth: maxWidth,
      leftMargin: margin,
    );
    final paper = img.Image(width: maxWidth, height: raster.height);
    img.fill(paper, color: img.ColorRgb8(255, 255, 255));
    final contentWidth = raster.widthBytes * 8;
    const offset = 0;
    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < contentWidth && x + offset < maxWidth; x++) {
        final byte = raster.data[y * raster.widthBytes + (x ~/ 8)];
        if ((byte & (0x80 >> (x % 8))) != 0) {
          paper.setPixelRgb(x + offset, y, 0, 0, 0);
        }
      }
    }
    return Uint8List.fromList(img.encodePng(paper));
  }

  static ThermalRaster _positionRaster(
    ThermalRaster source, {
    required int paperWidth,
    required int leftMargin,
  }) {
    if (leftMargin == 0) return source;
    final widthBytes = (paperWidth + 7) ~/ 8;
    final contentWidth = source.widthBytes * 8;
    final offset = leftMargin;
    final data = List<int>.filled(widthBytes * source.height, 0);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < contentWidth && x + offset < paperWidth; x++) {
        final byte = source.data[y * source.widthBytes + (x ~/ 8)];
        if ((byte & (0x80 >> (x % 8))) != 0) {
          data[y * widthBytes + ((x + offset) ~/ 8)] |=
              0x80 >> ((x + offset) % 8);
        }
      }
    }
    return ThermalRaster(widthBytes: widthBytes, height: source.height, data: data);
  }

  static List<int> imageToEscPos(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'center',
    String mode = 'floydSteinberg',
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(encodedImage));
    if (decoded == null) {
      throw const FormatException('صيغة الصورة غير مدعومة أو الملف تالف');
    }
    final scaledWidth = math.min(maxWidth, decoded.width);
    final scaled = scaledWidth == decoded.width
        ? decoded
        : img.copyResize(
            decoded,
            width: scaledWidth,
            interpolation: img.Interpolation.average,
          );

    // Shift the original-size raster 8 dots right without scaling it.
    const margin = 8;
    final sourceRaster = _decodedToRaster(
      scaled,
      maxWidth: maxWidth,
      maxHeight: maxHeightDots,
      threshold: threshold,
      mode: mode,
    );
    final raster = _positionRaster(
      sourceRaster,
      paperWidth: maxWidth,
      leftMargin: margin,
    );
    // Positioning is already encoded in the full-width raster.
    const justification = 0;
    return <int>[
      0x1B, 0x40, // Initialize printer.
      0x1B, 0x61, justification, // ESC a: printer-side justification.
      0x1D, 0x76, 0x30, 0x00,
      raster.widthBytes & 0xFF,
      (raster.widthBytes >> 8) & 0xFF,
      raster.height & 0xFF,
      (raster.height >> 8) & 0xFF,
      ...raster.data,
      0x0A, 0x0A,
      0x1B, 0x61, 0x00, // Reset to left for subsequent raw jobs.
    ];
  }

  /// Runs CPU-heavy image decoding and raster conversion off the UI isolate.
  static Future<List<int>> imageToEscPosAsync(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'center',
    String mode = 'floydSteinberg',
  }) {
    return compute(_imageToEscPosWorker, <String, Object>{
      'bytes': Uint8List.fromList(encodedImage),
      'threshold': threshold,
      'maxWidth': maxWidth,
      'alignment': alignment,
      'mode': mode,
    });
  }

  static Future<List<int>> textToPng(
    String text, {
    int widthDots = maxWidthDots,
    int maxHeight = RasterPrint.maxHeightDots,
    int fontSize = 28,
    String alignment = 'center',
  }) async {
    final content = text.trim();
    if (content.isEmpty) {
      throw ArgumentError('لا يوجد نص للطباعة');
    }
    final painter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize.toDouble(),
          height: 1.35,
        ),
      ),
      textDirection: TextDirection.ltr,
      // Keep the raster itself content-sized; ESC a on the printer performs
      // the final left/center/right positioning.
      textAlign: TextAlign.left,
    );
    painter.layout(maxWidth: widthDots.toDouble());
    final height = math.max(48, painter.height.ceil() + 24).toInt();
    if (height > maxHeight) {
      throw ArgumentError('النص طويل جداً؛ قسّمه إلى صفحات أقصر');
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, const Offset(8, 8));
    final picture = recorder.endRecording();
    final rasterWidth = math.min(
      widthDots,
      math.max(1, painter.width.ceil() + 16),
    ).toInt();
    final rendered = await picture.toImage(rasterWidth, height);
    final byteData = await rendered.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.dispose();
    picture.dispose();
    if (byteData == null) {
      throw StateError('تعذر تجهيز النص للطباعة');
    }
    return byteData.buffer.asUint8List();
  }

  static Future<List<int>> textToEscPos(
    String text, {
    int fontSize = 28,
    int widthDots = maxWidthDots,
    String alignment = 'center',
    String mode = 'floydSteinberg',
  }) async {
    final png = await textToPng(
      text,
      fontSize: fontSize,
      widthDots: widthDots,
      alignment: alignment,
    );
    return imageToEscPosAsync(
      png,
      maxWidth: widthDots,
      alignment: alignment,
      mode: mode,
    );
  }
}

List<int> _imageToEscPosWorker(Map<String, Object> args) {
  return RasterPrint.imageToEscPos(
    args['bytes']! as Uint8List,
    threshold: args['threshold']! as int,
    maxWidth: args['maxWidth']! as int,
    alignment: args['alignment']! as String,
    mode: args['mode']! as String,
  );
}
