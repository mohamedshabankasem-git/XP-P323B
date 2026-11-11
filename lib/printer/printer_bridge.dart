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

  Future<void> connect(PrinterDevice device) async {
    await _method.invokeMethod('connect', {
      'transport': device.transport,
      'address': device.address,
      'name': device.name,
    });
  }

  Future<Map<dynamic, dynamic>> connectionStatus({bool restore = false}) async {
    final result = await _method.invokeMethod<Map<dynamic, dynamic>>(
      restore ? 'restoreConnection' : 'connectionStatus',
    );
    return result ?? <dynamic, dynamic>{'connected': false};
  }

  Future<Map<String, dynamic>> settings() async {
    final value = await _method.invokeMethod<Map<dynamic, dynamic>>('getSettings');
    return {
      'paperWidthMm': (value?['paperWidthMm'] as num?)?.toInt() ?? 80,
      'printAlignment': value?['printAlignment']?.toString() ?? 'center',
    };
  }

  Future<void> setPaperWidthMm(int width) =>
      _method.invokeMethod('setPaperWidth', {'paperWidthMm': width});

  Future<void> setPrintAlignment(String alignment) =>
      _method.invokeMethod('setPrintAlignment', {'alignment': alignment});

  Future<void> write(List<int> bytes) =>
      _method.invokeMethod('write', {'bytes': Uint8List.fromList(bytes)});

  Future<List<String>> renderPdf(String path, {int widthDots = 576}) async {
    final pages = await _method.invokeMethod<List<dynamic>>(
      'renderPdf',
      {'path': path, 'widthDots': widthDots},
    );
    return (pages ?? []).map((page) => page.toString()).toList();
  }
}
