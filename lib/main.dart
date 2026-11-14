import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'printer/printer_bridge.dart';
import 'printer/escpos.dart';
import 'printer/raster_print.dart';

void main() => runApp(const XpApp());

class XpApp extends StatelessWidget {
  const XpApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'XP Printer',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff1769aa),
          ),
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final bridge = PrinterBridge();
  final devices = <PrinterDevice>[];
  final sharedItems = <Map<String, dynamic>>[];
  PrinterDevice? selected;
  StreamSubscription? shareSub;
  String sharedText = '';
  String shareStatus = 'لم يتم استقبال مشاركة بعد';
  int tab = 0;
  String transportFilter = 'bluetooth';
  String? connectingAddress;
  int paperWidthMm = 58;
  int paperWidthDots = 384;
  String printAlignment = 'left';
  String rasterMode = 'floydSteinberg';
  String appLanguage = 'ar';
  String? customPrintImagePath;
  String? customPrintImageName;
  String tr(String ar) => appLanguage == 'ar' ? ar : ({'المشاركة':'Share','الإعدادات':'Settings','إعدادات الطباعة':'Print settings','الطباعة من المشاركة':'Print from sharing','إعادة طباعة العناصر المستلمة':'Print','إدراج صورة':'Add image','عرض اللغة':'Language','العربية':'Arabic','الإنجليزية':'English','الاتصال بالطابعة':'Printer connection','لا توجد جلسة طباعة نشطة':'No active printer session','غير متصل بالتطبيق':'Not connected','متصل عبر USB':'Connected via USB','متصل عبر Bluetooth':'Connected via Bluetooth','طريقة الاتصال':'Connection type','البحث واستعادة الاتصال':'Search and reconnect','جارٍ البحث والاستعادة...':'Searching and reconnecting...','بحث عن الطابعات':'Search for printers','إعادة الاتصال بالطابعة المحفوظة':'Reconnect saved printer','عرض الورق':'Paper width','محاذاة الطباعة':'Print alignment','يمين':'Right','منتصف':'Center','يسار':'Left','طريقة تحويل الصورة إلى أبيض وأسود':'Image conversion mode','إدارة الطابعة':'Printer management','طباعة صفحة اختبار':'Print test page','معاينة الطباعة':'Print preview','جارٍ تجهيز المعاينة...':'Preparing preview...','تمت إضافة الصورة إلى مهمة الطباعة':'Image added to print job','اختر عرض رول الورق المستخدم في طباعة الملفات المشتركة.':'Choose the roll width used for shared files.'})[ar] ?? ar);
  bool busy = false;
  bool printingShare = false;
  String? sharePreviewPath;
  Uint8List? sharePreviewBytes;
  String? sharePreviewLabel;
  bool preparingPreview = false;

  int get printWidthDots => paperWidthDots;

  @override
  void initState() {
    super.initState();
    shareSub = bridge.shares.listen(_onShared, onError: (Object error) {
      if (mounted) toast('تعذر استقبال المشاركة: $error');
    });
    _loadSettings();
  }

  @override
  void dispose() {
    shareSub?.cancel();
    super.dispose();
  }

  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onShared(Map<dynamic, dynamic> message) {
    final rawItems = message['items'] as List? ?? const [];
    final items = rawItems
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final text = message['text']?.toString() ?? '';
    setState(() {
      sharedItems
        ..clear()
        ..addAll(items);
      sharedText = text;
      final names = items
          .map((item) => item['name']?.toString() ?? 'ملف')
          .toList();
      shareStatus = names.isNotEmpty
          ? names.join('، ')
          : (text.trim().isNotEmpty ? 'نص مستلم' : 'مشاركة فارغة');
      tab = 0;
    });

    _prepareSharePreview();

    // The share shortcut is intended to print immediately when a printer is
    // connected. If reconnection is needed, printShared attempts it first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) printShared(automatic: true);
    });
  }

  Future<void> _prepareSharePreview() async {
    if (!mounted) return;
    setState(() {
      preparingPreview = true;
      sharePreviewPath = null;
      sharePreviewBytes = null;
      sharePreviewLabel = null;
    });
    try {
      if (customPrintImagePath != null) {
        sharePreviewBytes = RasterPrint.imageToPreviewPng(await File(customPrintImagePath!).readAsBytes(), maxWidth: printWidthDots, alignment: printAlignment, mode: rasterMode);
        sharePreviewLabel = tr('معاينة الطباعة');
        return;
      }
      final item = sharedItems.isNotEmpty ? sharedItems.first : null;
      if (item == null) {
        if (sharedText.trim().isNotEmpty) {
          final textPng = await RasterPrint.textToPng(
            sharedText,
            widthDots: printWidthDots,
            alignment: printAlignment,
          );
          sharePreviewBytes = RasterPrint.imageToPreviewPng(
            textPng,
            maxWidth: printWidthDots,
            alignment: printAlignment,
            mode: rasterMode,
          );
          sharePreviewLabel = 'معاينة النص كما سيُطبع';
        }
      } else {
        final path = item['path']?.toString() ?? '';
        final mime = (item['mimeType']?.toString() ?? '').toLowerCase();
        if (path.isEmpty) throw StateError('مسار الملف غير موجود');
        if (mime.startsWith('image/')) {
          sharePreviewBytes = RasterPrint.imageToPreviewPng(
            await File(path).readAsBytes(),
            maxWidth: printWidthDots,
            alignment: printAlignment,
            mode: rasterMode,
          );
          sharePreviewLabel = 'معاينة حرارية مطابقة لإعدادات الطباعة';
        } else if (mime == 'application/pdf' || path.toLowerCase().endsWith('.pdf')) {
          final count = await bridge.pdfPageCount(path);
          if (count > 0) {
            final renderedPath = await bridge.renderPdfPage(
              path,
              pageIndex: 0,
              widthDots: printWidthDots,
            );
            sharePreviewBytes = RasterPrint.imageToPreviewPng(
              await File(renderedPath).readAsBytes(),
              maxWidth: printWidthDots,
              alignment: printAlignment,
              mode: rasterMode,
            );
            sharePreviewLabel = 'معاينة حرارية للصفحة الأولى من PDF ($count صفحة)';
          }
        } else {
          sharePreviewLabel = item['name']?.toString() ?? 'نوع ملف غير مدعوم للمعاينة';
        }
      }
    } catch (error) {
      sharePreviewLabel = 'تعذرت المعاينة: $error';
    } finally {
      if (mounted) setState(() => preparingPreview = false);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await bridge.settings();
      if (mounted) {
        setState(() {
          paperWidthDots = [400, 576].contains(settings['paperWidthDots']) ? settings['paperWidthDots'] as int : 384;
          paperWidthMm = paperWidthDots == 576 ? 80 : 58;
          printAlignment = settings['printAlignment'] as String;
          rasterMode = settings['rasterMode'] as String;
          transportFilter = settings['lastTransport'] as String;
        });
      }
      await refresh();
    } catch (error) {
      toast('تعذر تحميل إعدادات الورق: $error');
      await refresh();
    }
  }

  Future<void> searchDevices() async { setState(() => busy = true); try { devices..clear()..addAll(await bridge.devices(transport: transportFilter)); if (mounted) setState(() {}); } catch (error) { toast('تعذر البحث عن الأجهزة: $error'); } finally { if (mounted) setState(() => busy = false); } }
  Future<void> reconnectSavedPrinter() async { setState(() => busy = true); try { final status = await bridge.connectionStatus(restore: true, transport: transportFilter); if (status['connected'] == true) { selected = PrinterDevice(status['name']?.toString() ?? 'XP Printer', status['address']?.toString() ?? '', status['transport']?.toString() ?? 'bluetooth'); toast('تمت إعادة الاتصال بالطابعة'); } else { selected = null; toast('تعذرت إعادة الاتصال بالطابعة المحفوظة'); } } catch (error) { toast('تعذرت إعادة الاتصال: $error'); } finally { if (mounted) setState(() => busy = false); } }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      devices
        ..clear()
        ..addAll(await bridge.devices(transport: transportFilter));
      final status = await bridge.connectionStatus(restore: true, transport: transportFilter);
      if (status['connected'] == true) {
        selected = PrinterDevice(
          status['name']?.toString() ?? 'XP Printer',
          status['address']?.toString() ?? '',
          status['transport']?.toString() ?? 'bluetooth',
        );
      } else {
        selected = null;
      }
      if (mounted) setState(() {});
    } catch (error) {
      toast('تعذر البحث أو استعادة الاتصال: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> ensureConnected() async {
    try {
      final status = await bridge.connectionStatus(restore: true, transport: transportFilter);
      if (status['connected'] == true) {
        selected = PrinterDevice(
          status['name']?.toString() ?? 'XP Printer',
          status['address']?.toString() ?? '',
          status['transport']?.toString() ?? 'bluetooth',
        );
        if (mounted) setState(() {});
        return true;
      }
    } catch (error) {
      toast('تعذر التحقق من اتصال الطابعة: $error');
    }
    if (mounted) setState(() => selected = null);
    return false;
  }

  Future<void> connect(PrinterDevice device) async {
    if (connectingAddress != null) return;
    setState(() => connectingAddress = '${device.transport}:${device.address}');
    try {
      await bridge.connect(device);
      final connected = await ensureConnected();
      if (connected) {
        toast('تم الاتصال بالطابعة: ${device.name}');
      } else {
        toast('لم يكتمل الاتصال بالطابعة');
      }
    } catch (error) {
      toast('فشل الاتصال: $error');
      // USB may need the Android permission dialog; refresh after approval.
      await refresh();
    } finally {
      if (mounted) setState(() => connectingAddress = null);
    }
  }

  Future<void> _setTransport(String value) async {
    if (transportFilter == value) return;
    setState(() { transportFilter = value; busy = true; });
    try {
      await bridge.setTransport(value);
      devices..clear()..addAll(await bridge.devices(transport: value));
    } catch (error) {
      toast('تعذر تحديث قائمة الأجهزة: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> printBytes(List<int> bytes) async {
    if (!await ensureConnected()) {
      if (mounted) setState(() => tab = 1);
      toast('الطابعة غير متصلة بالتطبيق. افتح الإعدادات واختر الطابعة ثم اضغط اتصال.');
      return;
    }
    try {
      await bridge.write(bytes);
      toast('تم إرسال أمر الطباعة');
    } catch (error) {
      if (mounted) setState(() => selected = null);
      toast('فشل إرسال الطباعة: $error');
    }
  }

  Future<void> pickImageForPrint() async { try { final image = await bridge.pickImageForPrint(); if (image == null || image['path'] == null) return; final path = image['path']!.toString(); final bytes = await File(path).readAsBytes(); setState(() { customPrintImagePath = path; customPrintImageName = image['name']?.toString() ?? 'image'; sharePreviewBytes = RasterPrint.imageToPreviewPng(bytes, maxWidth: printWidthDots, alignment: printAlignment, mode: rasterMode); sharePreviewLabel = tr('معاينة الطباعة'); }); toast(tr('تمت إضافة الصورة إلى مهمة الطباعة')); } catch (error) { toast('تعذر اختيار الصورة: $error'); } }

  Future<void> printShared({bool automatic = false}) async {
    if (printingShare) return;
    if (sharedItems.isEmpty && sharedText.trim().isEmpty && customPrintImagePath == null) {
      if (!automatic) toast('لا توجد ملفات أو نصوص مستلمة للطباعة');
      return;
    }

    setState(() => printingShare = true);
    var printed = 0;
    try {
      if (!await ensureConnected()) {
        toast(
          automatic
              ? 'تم استقبال المشاركة، لكن لا يوجد اتصال طباعة نشط. افتح الإعدادات واتصل بالطابعة ثم أعد الطباعة.'
              : 'اتصل بالطابعة أولاً ثم أعد المحاولة.',
        );
        return;
      }

      for (final item in sharedItems) {
        final mime = (item['mimeType']?.toString() ?? '').toLowerCase();
        final path = item['path']?.toString() ?? '';
        if (path.isEmpty) throw StateError('مسار الملف المستلم غير موجود');

        if (mime.startsWith('image/')) {
          final bytes = await File(path).readAsBytes();
          await bridge.write(
            await RasterPrint.imageToEscPosAsync(bytes, maxWidth: printWidthDots, alignment: printAlignment, mode: rasterMode),
          );
          printed++;
        } else if (mime == 'application/pdf' ||
            path.toLowerCase().endsWith('.pdf')) {
          final pageCount = await bridge.pdfPageCount(path);
          if (pageCount < 1) {
            throw StateError('ملف PDF لا يحتوي على صفحات قابلة للطباعة');
          }
          // Render, convert and send each page before rendering the next one.
          for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
            final pagePath = await bridge.renderPdfPage(
              path,
              pageIndex: pageIndex,
              widthDots: printWidthDots,
            );
            try {
              final bytes = await File(pagePath).readAsBytes();
              final command = await RasterPrint.imageToEscPosAsync(
                bytes,
                maxWidth: printWidthDots,
                alignment: printAlignment,
                mode: rasterMode,
              );
              await bridge.write(command);
              printed++;
            } finally {
              try {
                await File(pagePath).delete();
              } catch (_) {}
            }
          }
        }
      }

      if (customPrintImagePath != null) { final bytes = await File(customPrintImagePath!).readAsBytes(); await bridge.write(await RasterPrint.imageToEscPosAsync(bytes, maxWidth: printWidthDots, alignment: printAlignment, mode: rasterMode)); printed++; }
      if (sharedText.trim().isNotEmpty) {
        await bridge.write(
          await RasterPrint.textToEscPos(
            sharedText,
            widthDots: printWidthDots,
            alignment: printAlignment,
            mode: rasterMode,
          ),
        );
        printed++;
      }

      if (printed > 0) {
        toast('تم إرسال $printed عنصر/صفحة للطباعة');
      } else {
        toast('نوع الملف غير مدعوم حالياً؛ استخدم صورة أو PDF أو نصاً');
      }
    } catch (error) {
      toast('تعذر طباعة المشاركة: $error');
    } finally {
      if (mounted) setState(() => printingShare = false);
    }
  }

  Future<void> changePaperWidth(int width, int dots) async {
    try {
      await bridge.setPaperWidth(width, dots);
      if (mounted) setState(() { paperWidthMm = width; paperWidthDots = dots; });
      toast('تم حفظ مقاس الورق');
    } catch (error) {
      toast('تعذر حفظ مقاس الورق: $error');
    }
  }

  Widget field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  IconData _deviceIcon(PrinterDevice device) {
    switch (device.deviceType.toLowerCase()) {
      case 'printer':
        return Icons.print;
      case 'phone':
      case 'mobile':
        return Icons.smartphone;
      case 'audio':
      case 'headset':
      case 'speaker':
        return Icons.headphones;
      case 'computer':
      case 'laptop':
        return Icons.computer;
      case 'keyboard':
        return Icons.keyboard;
      case 'mouse':
      case 'pointing':
        return Icons.mouse;
      case 'gamepad':
      case 'joystick':
        return Icons.sports_esports;
      case 'camera':
      case 'imaging':
        return Icons.camera_alt;
      case 'storage':
        return Icons.storage;
      case 'hub':
      case 'network':
      case 'router':
        return Icons.router;
      case 'usb':
        return Icons.usb;
      default:
        return device.transport == 'usb' ? Icons.usb : Icons.bluetooth_connected;
    }
  }

  Widget _printerSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('الاتصال بالطابعة'),
              style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: Icon(
              selected == null ? Icons.print_disabled : _deviceIcon(selected!),
              color: selected == null ? Colors.red : Colors.green,
            ),
            title: Text(selected?.name ?? tr('لا توجد جلسة طباعة نشطة')),
            subtitle: Text(
              selected == null
                  ? tr('غير متصل بالتطبيق') : selected!.transport == 'usb' ? tr('متصل عبر USB') : tr('متصل عبر Bluetooth'),
            ),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(transportFilter),
            initialValue: transportFilter,
            decoration: InputDecoration(labelText: tr('طريقة الاتصال'), border: const OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'bluetooth', child: Row(children: [Icon(Icons.bluetooth), SizedBox(width: 10), Text('Bluetooth')])),
              DropdownMenuItem(value: 'usb', child: Row(children: [Icon(Icons.usb), SizedBox(width: 10), Text('USB')])),
            ],
            onChanged: busy || connectingAddress != null ? null : (value) { if (value != null) _setTransport(value); },
          ),
          PopupMenuButton<String>(enabled: !busy && connectingAddress == null, onSelected: (action) { if (action == 'search') searchDevices(); else reconnectSavedPrinter(); }, itemBuilder: (_) => [PopupMenuItem(value: 'search', child: Text(tr('بحث عن الطابعات'))), PopupMenuItem(value: 'reconnect', child: Text(tr('إعادة الاتصال بالطابعة المحفوظة')))], child: ListTile(leading: const Icon(Icons.search), title: Text(busy ? '...' : tr('البحث واستعادة الاتصال')), trailing: const Icon(Icons.arrow_drop_down))),
          ...devices.where((device) => device.transport == transportFilter).map(
            (device) => Card(
              child: ListTile(
                leading: Icon(_deviceIcon(device)),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: TextButton(
                  onPressed: connectingAddress != null ? null : () => connect(device),
                  child: Text(
                    connectingAddress == '${device.transport}:${device.address}'
                        ? 'جارٍ الاتصال...'
                        : 'اتصال',
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: selected == null
                ? null
                : printTestPage,
            child: const Text('طباعة صفحة اختبار'),
          ),
          const Text(
            'يتم حفظ آخر طابعة تم الاتصال بها ومحاولة استعادة الاتصال تلقائياً عند فتح التطبيق أو استقبال ملف للمشاركة. الاقتران من إعدادات الهاتف وحده لا يعني وجود جلسة طباعة نشطة.',
          ),
        ],
      );

  Widget _sharePage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('الطباعة من المشاركة'),
              style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'اختر مشاركة ثم XP Printer من أي تطبيق. ينتقل التطبيق إلى هذه الشاشة ويبدأ الطباعة تلقائياً عند توفر اتصال بالطابعة.',
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.receipt_long_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(preparingPreview ? 'جارٍ تجهيز المعاينة...' : (sharePreviewLabel ?? 'معاينة الطباعة'))),
                    Text('$paperWidthMm مم', style: Theme.of(context).textTheme.labelMedium),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(minHeight: 150, maxHeight: 440),
                    width: double.infinity,
                    color: const Color(0xffeeeeee),
                    alignment: Alignment.topCenter,
                    child: preparingPreview
                        ? const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
                        : sharePreviewBytes != null
                            ? Image.memory(
                                sharePreviewBytes!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.none,
                                errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('تعذر عرض الملف')),
                              )
                            : Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(sharePreviewLabel ?? 'شارك صورة أو PDF أو نصاً لعرض معاينة الطباعة هنا'),
                                  ),
                  ),
                  if (sharedItems.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('المعاينة للعنصر الأول من ${sharedItems.length} عناصر؛ ستتم طباعة جميع العناصر المدعومة.'),
                    ),
                ],
              ),
            ),
          ),
          OutlinedButton.icon(onPressed: pickImageForPrint, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(tr('إدراج صورة'))),
          if (customPrintImageName != null) ListTile(dense: true, leading: const Icon(Icons.image_outlined), title: Text(customPrintImageName!), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { setState(() { customPrintImagePath = null; customPrintImageName = null; }); _prepareSharePreview(); })),
          FilledButton.icon(onPressed: printingShare || (sharedItems.isEmpty && sharedText.trim().isEmpty && customPrintImagePath == null) ? null : () => printShared(),
            icon: printingShare
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(
              printingShare ? 'جارٍ تجهيز الطباعة...' : tr('إعادة طباعة العناصر المستلمة'),
            ),
          ),
          const SizedBox(height: 10),
          Text('مقاس الورق الحالي: $paperWidthMm مم'),
        ],
      );

  Future<void> changeRasterMode(String mode) async {
    try {
      await bridge.setRasterMode(mode);
      if (mounted) setState(() => rasterMode = mode);
      await _prepareSharePreview();
      toast('تم حفظ طريقة تحويل الصورة للطباعة');
    } catch (error) {
      toast('تعذر حفظ طريقة التحويل: $error');
    }
  }

  Future<void> printTestPage() async {
    try {
      final icon = await bridge.appIcon();
      final logo = icon.isEmpty ? <int>[] : await RasterPrint.imageToEscPosAsync(
        icon, maxWidth: printWidthDots, alignment: 'center', mode: rasterMode,
      );
      await printBytes([...EscPos.testPage(), ...logo]);
    } catch (error) {
      toast('تعذر تجهيز صفحة الاختبار: $error');
    }
  }

  Future<void> changeAlignment(String alignment) async {
    try {
      await bridge.setPrintAlignment(alignment);
      if (mounted) setState(() => printAlignment = alignment);
      toast('تم حفظ محاذاة الطباعة');
    } catch (error) {
      toast('تعذر حفظ محاذاة الطباعة: $error');
    }
  }

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(isExpanded: true, value: appLanguage, decoration: InputDecoration(labelText: tr('عرض اللغة'), border: const OutlineInputBorder()), items: [DropdownMenuItem(value: 'ar', child: Text(tr('العربية'))), DropdownMenuItem(value: 'en', child: Text(tr('الإنجليزية')))], onChanged: (value) { if (value != null) setState(() => appLanguage = value); }),
          const SizedBox(height: 12),
          Text(tr('إعدادات الطباعة'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(tr('اختر عرض رول الورق المستخدم في طباعة الملفات المشتركة.')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            key: ValueKey('$paperWidthMm:$paperWidthDots'),
            initialValue: paperWidthDots,
            decoration: InputDecoration(labelText: tr('عرض الورق'), border: const OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 384, child: Text('58 مم - 384 نقطة')),
              DropdownMenuItem(value: 400, child: Text('58 مم - 400 نقطة')),
              DropdownMenuItem(value: 576, child: Text('80 مم - 576 نقطة')),
            ],
            onChanged: (value) { if (value != null) changePaperWidth(value == 576 ? 80 : 58, value); },
          ),
          const SizedBox(height: 12),
          Text(tr('محاذاة الطباعة')),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(printAlignment),
            initialValue: printAlignment,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: 'تُطبّق على النصوص والصور والملفات المشتركة',
            ),
            items: const [
              DropdownMenuItem(value: 'right', child: Text(tr('يمين'))),
              DropdownMenuItem(value: 'center', child: Text(tr('منتصف'))),
              DropdownMenuItem(value: 'left', child: Text(tr('يسار'))),
            ],
            onChanged: (value) {
              if (value != null) changeAlignment(value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(rasterMode),
            initialValue: rasterMode,
            decoration: const InputDecoration(
              labelText: 'طريقة تحويل الصورة إلى أبيض وأسود',
              border: OutlineInputBorder(),
              helperText: 'المعاينة والطباعة تستخدمان نفس طريقة التحويل',
            ),
            items: const [
              DropdownMenuItem(value: 'floydSteinberg', child: Text('Dithering - Floyd-Steinberg (تفاصيل وتدرجات أفضل)', maxLines: 1, overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'atkinson', child: Text('Dithering - Atkinson (نقاط أخف)', maxLines: 1, overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'ordered', child: Text('Ordered Dithering (نمط شبكي)', maxLines: 1, overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'threshold', child: Text('Black & White (أبيض وأسود مباشر)', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) { if (value != null) changeRasterMode(value); },
          ),
          const Divider(),
          Text('إدارة الطابعة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _printerSection(),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('ملاحظة لطابعة XP-P323B'),
            subtitle: Text(
              'أقصى عرض طباعة للطابعة 72 مم. عند اختيار رول 80 مم يستخدم التطبيق كامل عرض الطباعة المتاح، ولا يتجاوز 576 نقطة.',
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: appLanguage == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('XP Printer'),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.circle,
                  size: 11,
                  color: selected == null ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: tab,
            children: [
              _sharePage(),
              _settingsPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.share), label: tr('المشاركة')),
              NavigationDestination(icon: const Icon(Icons.settings_outlined), label: tr('الإعدادات')),
            ],
          ),
        ),
      );
}
