import 'dart:convert';

import 'raster_print.dart';

class Tspl {
  /// Legacy ASCII label command retained as a simple diagnostic.
  static List<int> label({
    required String name,
    required String price,
    required String barcode,
  }) {
    String ascii(String value) => value
        .replaceAll('"', "'")
        .replaceAll(RegExp(r'[^ -~]'), '?');
    final code = barcode.replaceAll(RegExp(r'[^0-9A-Za-z.$/+% -]'), '');
    final commands = [
      'SIZE 50 mm,30 mm',
      'GAP 2 mm,0 mm',
      'DIRECTION 1',
      'CLS',
      'TEXT 24,16,"3",0,1,1,"' + ascii(name) + '"',
      'TEXT 24,48,"3",0,1,1,"' + ascii(price) + '"',
      if (code.isNotEmpty) 'BARCODE 24,82,"128",48,1,0,2,2,"' + code + '"',
      'PRINT 1,1',
      '',
    ].join('\r\n');
    return latin1.encode(commands);
  }

  /// Builds a 50 x 30 mm TSPL label with Arabic text rasterized by Flutter.
  static Future<List<int>> labelRaster({
    required String name,
    required String price,
    required String barcode,
  }) async {
    final textPng = await RasterPrint.textToPng(
      '$name\n$price',
      widthDots: 400,
      maxHeight: 108,
      fontSize: 27,
    );
    final raster = RasterPrint.imageToRaster(
      textPng,
      maxWidth: 400,
      maxHeight: 108,
    );
    final code = barcode.replaceAll(RegExp(r'[^0-9A-Za-z.$/+% -]'), '');

    final prefix = [
      'SIZE 50 mm,30 mm',
      'GAP 2 mm,0 mm',
      'DIRECTION 1',
      'CLS',
    ].join('\r\n') +
        '\r\nBITMAP 0,0,${raster.widthBytes},${raster.height},0,';
    final barcodeCommand = code.isEmpty
        ? ''
        : 'BARCODE 24,130,"128",60,1,0,2,2,"$code"\r\n';
    final suffix = '\r\n${barcodeCommand}PRINT 1,1\r\n';

    return <int>[
      ...latin1.encode(prefix),
      ...raster.data,
      ...latin1.encode(suffix),
    ];
  }
}
