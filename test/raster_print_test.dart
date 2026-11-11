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

    expect(
      command.take(10).toList(),
      <int>[0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00, 1, 0, 1, 0],
    );
    expect(command[10], 0xFF);
    expect(command.sublist(command.length - 2), <int>[0x0A, 0x0A]);
  });

  test('rejects an invalid image payload', () {
    expect(
      () => RasterPrint.imageToEscPos(<int>[1, 2, 3]),
      throwsFormatException,
    );
  });
}
