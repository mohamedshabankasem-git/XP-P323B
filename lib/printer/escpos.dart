import 'dart:convert';

class EscPos {
  static List<int> testPage() => [
    0x1B, 0x40,
    ...latin1.encode('XP-P323B TEST\r\n'),
    ...latin1.encode('--------------------------------\r\n'),
    ...latin1.encode('ESC/POS CONNECTION OK\r\n\r\n\r\n'),
  ];

  static List<int> invoice({
    required String number,
    required String item,
    required String price,
  }) {
    String ascii(String value) =>
        value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    final body = [
      'INVOICE #' + ascii(number),
      '--------------------------------',
      ascii(item),
      'PRICE: ' + ascii(price),
      '--------------------------------',
      'THANK YOU',
      '',
      '',
    ].join('\r\n');
    return [
      0x1B, 0x40, 0x1B, 0x61, 0x01,
      ...latin1.encode(body),
      0x1B, 0x61, 0x00,
    ];
  }
}
