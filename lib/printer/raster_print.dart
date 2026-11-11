import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    );
  }

  static ThermalRaster _decodedToRaster(
    img.Image decoded, {
    required int maxWidth,
    required int maxHeight,
    required int threshold,
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
    return ThermalRaster(
      widthBytes: bytesPerRow,
      height: raster.height,
      data: pixels,
    );
  }

  static List<int> imageToEscPos(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'center',
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
    final canvas = img.Image(width: maxWidth, height: scaled.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    final offset = alignment == 'left'
        ? 0
        : alignment == 'right'
            ? maxWidth - scaled.width
            : (maxWidth - scaled.width) ~/ 2;
    img.compositeImage(canvas, scaled, dstX: offset);

    // Convert the in-memory image directly; avoid PNG encode + second decode.
    final raster = _decodedToRaster(
      canvas,
      maxWidth: maxWidth,
      maxHeight: maxHeightDots,
      threshold: threshold,
    );
    return <int>[
      0x1B, 0x40,
      0x1D, 0x76, 0x30, 0x00,
      raster.widthBytes & 0xFF,
      (raster.widthBytes >> 8) & 0xFF,
      raster.height & 0xFF,
      (raster.height >> 8) & 0xFF,
      ...raster.data,
      0x0A, 0x0A,
    ];
  }

  /// Runs CPU-heavy image decoding and raster conversion off the UI isolate.
  static Future<List<int>> imageToEscPosAsync(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'center',
  }) {
    return compute(_imageToEscPosWorker, <String, Object>{
      'bytes': Uint8List.fromList(encodedImage),
      'threshold': threshold,
      'maxWidth': maxWidth,
      'alignment': alignment,
    });
  }

  static List<int> textToEscPosSyncUnsupported() =>
      throw UnsupportedError('Use textToEscPos for Flutter text rendering');

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
      textDirection: TextDirection.rtl,
      textAlign: alignment == 'left'
          ? TextAlign.left
          : alignment == 'right'
              ? TextAlign.right
              : TextAlign.center,
    );
    painter.layout(maxWidth: (widthDots - 16).toDouble());
    final height = math.max(48, painter.height.ceil() + 24).toInt();
    if (height > maxHeight) {
      throw ArgumentError('النص طويل جداً؛ قسّمه إلى صفحات أقصر');
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, const Offset(8, 8));
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(widthDots, height);
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
  }) async {
    final png = await textToPng(
      text,
      fontSize: fontSize,
      widthDots: widthDots,
      alignment: alignment,
    );
    return imageToEscPosAsync(png, maxWidth: widthDots);
  }
}

List<int> _imageToEscPosWorker(Map<String, Object> args) {
  return RasterPrint.imageToEscPos(
    args['bytes']! as Uint8List,
    threshold: args['threshold']! as int,
    maxWidth: args['maxWidth']! as int,
    alignment: args['alignment']! as String,
  );
}
