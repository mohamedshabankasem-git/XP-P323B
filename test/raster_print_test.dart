import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xp_p323b/printer/raster_print.dart';

void main() {
  test('encodes left, center and right image alignment in the raster', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }
    final encoded = img.encodePng(source);

    final left = RasterPrint.imageToEscPos(
      encoded, maxWidth: 384, alignment: 'left',
    );
    final center = RasterPrint.imageToEscPos(
      encoded, maxWidth: 384, alignment: 'center',
    );
    final right = RasterPrint.imageToEscPos(
      encoded, maxWidth: 384, alignment: 'right',
    );

    // ESC/POS justification stays left because the raster carries alignment.
    for (final command in [left, center, right]) {
      expect(command.sublist(2, 5), <int>[0x1B, 0x61, 0]);
      expect(command[9], 48);
      expect(command[10], 0);
      expect(command[11], 1);
      expect(command.sublist(command.length - 5), <int>[
        0x0A, 0x0A, 0x1B, 0x61, 0x00,
      ]);
    }
    // A one-byte-wide black source occupies the left, center, or right
    // byte of the 48-byte print row respectively.
    expect(left[13], 0xFF);
    expect(center[13 + 23], 0x0F);
    expect(center[13 + 24], 0xF0);
    expect(right[13 + 47], 0x01);
  });

  test('preview applies the same horizontal alignment as print data', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }
    final encoded = img.encodePng(source);
    final expectedX = {'left': 0, 'center': 188, 'right': 376};
    for (final alignment in ['left', 'center', 'right']) {
      final preview = img.decodePng(RasterPrint.imageToPreviewPng(
        encoded, maxWidth: 384, alignment: alignment,
      ))!;
      expect(preview.width, 384);
      expect(preview.height, 1);
      expect(preview.getPixel(expectedX[alignment]!, 0).r, 0);
      expect(preview.getPixel(expectedX[alignment]! + 7, 0).r, 0);
    }
  });

  test('respects a narrower configured paper width', () {
    final source = img.Image(width: 16, height: 2);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 16; x++) {
        source.setPixelRgb(x, y, 0, 0, 0);
      }
    }
    final raster = RasterPrint.imageToRaster(
      img.encodePng(source),
      maxWidth: 8,
    );
    expect(raster.widthBytes, 1);
    expect(raster.height, 1);
  });

  test('rejects an invalid image payload', () {
    expect(
      () => RasterPrint.imageToEscPos(<int>[1, 2, 3]),
      throwsFormatException,
    );
  });
}
