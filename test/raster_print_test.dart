import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xp_p323b/printer/raster_print.dart';

void main() {
  test('encodes a monochrome image as an ESC/POS raster command', () {
    final source = img.Image(width: 8, height: 1);
    for (var x = 0; x < 8; x++) {
      source.setPixelRgb(x, 0, 0, 0, 0);
    }

    final encoded = img.encodePng(source);
    final command = RasterPrint.imageToEscPos(encoded);

    // The image is centered on the printer's full 576-dot printable width.
    expect(
      command.take(10).toList(),
      <int>[0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00, 72, 0, 1, 0],
    );
    expect(command[10 + 35], 0x0F);
    expect(command[10 + 36], 0xF0);
    expect(command.sublist(10, 10 + 35).every((byte) => byte == 0), isTrue);
    expect(command.sublist(10 + 37, 10 + 72).every((byte) => byte == 0), isTrue);
    expect(command.sublist(command.length - 2), <int>[0x0A, 0x0A]);
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
