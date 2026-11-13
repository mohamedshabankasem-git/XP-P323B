import 'package:flutter/services.dart';

class PrinterDevice {
  const PrinterDevice(this.name, this.address, this.transport, [this.deviceType = 'other']);
  final String name, address, transport, deviceType;

  factory PrinterDevice.fromMap(Map<dynamic, dynamic> map) => PrinterDevice(
        map['name']?.toString() ?? 'Printer',
        map['address']?.toString() ?? '',
        map['transport']?.toString() ?? 'bluetooth',
        map['deviceType']?.toString() ?? 'other',
      );
}

class PrinterBridge {
  static const _method = MethodChannel('xp_p323b/printer');
  static const _share = EventChannel('xp_p323b/share');

  Stream<Map<dynamic, dynamic>> get shares => _share
      .receiveBroadcastStream()
      .map((event) => Map<dynamic, dynamic>.from(event));

  Future<List<PrinterDevice>> devices({String transport = 'bluetooth'}) async {
    final list = await _method.invokeMethod<List<dynamic>>(
      'discoverDevices', {'transport': transport},
    );
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

  Future<Map<dynamic, dynamic>> connectionStatus({bool restore = false, String transport = 'bluetooth'}) async {
    final result = await _method.invokeMethod<Map<dynamic, dynamic>>(
      restore ? 'restoreConnection' : 'connectionStatus',
      restore ? {'transport': transport} : null,
    );
    return result ?? <dynamic, dynamic>{'connected': false};
  }

  Future<Map<String, dynamic>> settings() async {
    final value = await _method.invokeMethod<Map<dynamic, dynamic>>('getSettings');
    return {
      'paperWidthMm': (value?['paperWidthMm'] as num?)?.toInt() ?? 58,
      'paperWidthDots': (value?['paperWidthDots'] as num?)?.toInt() ?? 384,
      'printAlignment': value?['printAlignment']?.toString() ?? 'left',
      'lastTransport': value?['lastTransport']?.toString() == 'usb' ? 'usb' : 'bluetooth',
      'rasterMode': value?['rasterMode']?.toString() ?? 'floydSteinberg',
    };
  }

  Future<void> setPaperWidth(int width, int dots) =>
      _method.invokeMethod('setPaperWidth', {'paperWidthMm': width, 'paperWidthDots': dots});

  Future<void> setTransport(String transport) =>
      _method.invokeMethod('setTransport', {'transport': transport});

  Future<void> setRasterMode(String mode) =>
      _method.invokeMethod('setRasterMode', {'mode': mode});

  Future<Uint8List> appIcon() async =>
      (await _method.invokeMethod<Uint8List>('getAppIcon')) ?? Uint8List(0);

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
  Future<int> pdfPageCount(String path) async {
    final count = await _method.invokeMethod<int>(
      'pdfPageCount',
      {'path': path},
    );
    return count ?? 0;
  }

  Future<String> renderPdfPage(
    String path, {
    required int pageIndex,
    int widthDots = 576,
  }) async {
    final pagePath = await _method.invokeMethod<String>(
      'renderPdfPage',
      {
        'path': path,
        'pageIndex': pageIndex,
        'widthDots': widthDots,
      },
    );
    if (pagePath == null || pagePath.isEmpty) {
      throw StateError('تعذر تجهيز صفحة PDF للطباعة');
    }
    return pagePath;
  }

}
