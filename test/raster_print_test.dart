import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xp_p323b/printer/raster_print.dart';

void main() {
  test('encodes a monochrome image and delegates alignment to ESC/POS', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }

    final command = RasterPrint.imageToEscPos(img.encodePng(source));

    // ESC @, ESC a center, GS v 0 raster header (one byte wide).
    expect(
      command.take(10).toList(),
      <int>[0x1B, 0x40, 0x1B, 0x61, 1, 0x1D, 0x76, 0x30, 0x00, 1],
    );
    expect(command[10], 0x00); // Width high byte.
    expect(command[11], 0x01); // Height low byte.
    expect(command[12], 0xFF);
    expect(command.sublist(command.length - 5), <int>[
      0x0A, 0x0A, 0x1B, 0x61, 0x00,
    ]);
  });

  test('uses printer-side left and right image alignment', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }
    final encoded = img.encodePng(source);

    final left = RasterPrint.imageToEscPos(
      encoded,
      maxWidth: 16,
      alignment: 'left',
    );
    final right = RasterPrint.imageToEscPos(
      encoded,
      maxWidth: 16,
      alignment: 'right',
    );

    // Raster data remains identical and content-sized; only ESC a changes.
    expect(left.sublist(2, 5), <int>[0x1B, 0x61, 0]);
    expect(right.sublist(2, 5), <int>[0x1B, 0x61, 2]);
    expect(left.sublist(10, 11), <int>[0xFF]);
    expect(right.sublist(10, 11), <int>[0xFF]);
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
