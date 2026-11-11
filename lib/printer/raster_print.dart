import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Converts shared images and Flutter-rendered text to ESC/POS raster data.
/// XP-P323B has a 72 mm / 576-dot maximum print width at 203 DPI.
class RasterPrint {
  static const int maxWidthDots = 576;
  static const int maxHeightDots = 4096;

  static List<int> imageToEscPos(
    List<int> encodedImage, {
    int threshold = 160,
  }) {
    final decoded = img.decodeImage(encodedImage);
    if (decoded == null) {
      throw const FormatException('صيغة الصورة غير مدعومة أو الملف تالف');
    }

    final scale = math.min(
      1.0,
      math.min(
        maxWidthDots / decoded.width,
        maxHeightDots / decoded.height,
      ),
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

    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < raster.width; x++) {
        final pixel = raster.getPixel(x, y);
        final alpha = pixel.a / 255.0;
        final red = pixel.r * alpha + 255 * (1 - alpha);
        final green = pixel.g * alpha + 255 * (1 - alpha);
        final blue = pixel.b * alpha + 255 * (1 - alpha);
        final luminance = 0.299 * red + 0.587 * green + 0.114 * blue;
        if (luminance < threshold) {
          pixels[y * bytesPerRow + (x ~/ 8)] |= 0x80 >> (x % 8);
        }
      }
    }

    // GS v 0: xL, xH are bytes per row; yL, yH are raster rows.
    return <int>[
      0x1B, 0x40,
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      raster.height & 0xFF,
      (raster.height >> 8) & 0xFF,
      ...pixels,
      0x0A, 0x0A,
    ];
  }

  static Future<List<int>> textToEscPos(
    String text, {
    int fontSize = 28,
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
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
    );
    painter.layout(maxWidth: maxWidthDots.toDouble());

    final width = maxWidthDots;
    final height = math.max(48, painter.height.ceil() + 24).toInt();
    if (height > maxHeightDots) {
      throw ArgumentError('النص طويل جداً؛ قسّمه إلى صفحات أقصر');
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, const Offset(8, 8));
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final byteData = await rendered.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.dispose();
    picture.dispose();

    if (byteData == null) {
      throw StateError('تعذر تجهيز النص للطباعة');
    }
    return imageToEscPos(byteData.buffer.asUint8List());
  }
}
