import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xp_p323b/printer/raster_print.dart';

void main() {
  test('shifts original-size raster 8 dots right on both paper widths', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }
    final encoded = img.encodePng(source);

    for (final paperWidth in <int>[384, 576]) {
      final command = RasterPrint.imageToEscPos(
        encoded,
        maxWidth: paperWidth,
        alignment: 'left',
      );
      final widthBytes = paperWidth ~/ 8;
      expect(command.sublist(2, 5), <int>[0x1B, 0x61, 0]);
      expect(command[9], widthBytes);
      expect(command[10], 0);
      expect(command[13], 0x00);
      expect(command[14], 0xFF);
      expect(command.sublist(command.length - 5), <int>[
        0x0A, 0x0A, 0x1B, 0x61, 0x00,
      ]);
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
