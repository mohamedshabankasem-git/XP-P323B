import 'dart:convert';

class Tspl {
  static List<int> label({
    required String name,
    required String price,
    required String barcode,
  }) {
    String ascii(String value) => value
        .replaceAll('"', "'")
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    final code = barcode.replaceAll(RegExp(r'[^0-9A-Za-z\-.$/+% ]'), '');
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
}
