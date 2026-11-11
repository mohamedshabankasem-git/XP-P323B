import 'dart:typed_data';

import 'package:flutter/services.dart';

class PrinterDevice {
  const PrinterDevice(this.name, this.address, this.transport);
  final String name, address, transport;

  factory PrinterDevice.fromMap(Map<dynamic, dynamic> map) => PrinterDevice(
        map['name']?.toString() ?? 'Printer',
        map['address']?.toString() ?? '',
        map['transport']?.toString() ?? 'bluetooth',
      );
}

class PrinterBridge {
  static const _method = MethodChannel('xp_p323b/printer');
  static const _share = EventChannel('xp_p323b/share');

  Stream<Map<dynamic, dynamic>> get shares => _share
      .receiveBroadcastStream()
      .map((event) => Map<dynamic, dynamic>.from(event));

  Future<List<PrinterDevice>> devices() async {
    final list = await _method.invokeMethod<List<dynamic>>('discoverDevices');
    return (list ?? [])
        .map((item) => PrinterDevice.fromMap(
              Map<dynamic, dynamic>.from(item),
            ))
        .toList();
  }

  Future<void> connect(PrinterDevice device) =>
      _method.invokeMethod('connect', {
        'transport': device.transport,
        'address': device.address,
      });

  Future<void> write(List<int> bytes) =>
      _method.invokeMethod('write', {
        'bytes': Uint8List.fromList(bytes),
      });

  Future<List<String>> renderPdf(String path) async {
    final pages = await _method.invokeMethod<List<dynamic>>(
      'renderPdf',
      {'path': path},
    );
    return (pages ?? []).map((page) => page.toString()).toList();
  }
}
