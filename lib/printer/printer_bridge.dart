import 'package:flutter/services.dart';

class PrinterDevice {
  const PrinterDevice(this.name, this.address, this.transport);
  final String name, address, transport;
  factory PrinterDevice.fromMap(Map<dynamic, dynamic> m) => PrinterDevice(
    m['name']?.toString() ?? 'Printer',
    m['address']?.toString() ?? '',
    m['transport']?.toString() ?? 'bluetooth',
  );
}
class PrinterBridge {
  static const _method = MethodChannel('xp_p323b/printer');
  static const _share = EventChannel('xp_p323b/share');
  Stream<Map<dynamic, dynamic>> get shares => _share.receiveBroadcastStream()
      .map((e) => Map<dynamic, dynamic>.from(e));
  Future<List<PrinterDevice>> devices() async {
    final list = await _method.invokeMethod<List<dynamic>>('discoverDevices');
    return (list ?? []).map((e) => PrinterDevice.fromMap(Map<dynamic, dynamic>.from(e))).toList();
  }
  Future<void> connect(PrinterDevice d) => _method.invokeMethod('connect', {
    'transport': d.transport, 'address': d.address,
  });
  Future<void> write(List<int> bytes) => _method.invokeMethod('write', {'bytes': bytes});
}
