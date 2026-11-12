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
  bool connecting = false;
  int paperWidthMm = 80;
  int paperWidthDots = 576;
  String printAlignment = 'center';
  bool busy = false;
  bool printingShare = false;

  int get printWidthDots => paperWidthDots;

  @override
  void initState() {
    super.initState();
    shareSub = bridge.shares.listen(_onShared, onError: (Object error) {
      if (mounted) toast('تعذر استقبال المشاركة: $error');
    });
    refresh();
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

    // The share shortcut is intended to print immediately when a printer is
    // connected. If reconnection is needed, printShared attempts it first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) printShared(automatic: true);
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await bridge.settings();
      if (mounted) {
        setState(() {
          paperWidthMm = settings['paperWidthMm'] as int;
          paperWidthDots = settings['paperWidthDots'] as int;
          printAlignment = settings['printAlignment'] as String;
        });
      }
    } catch (error) {
      toast('تعذر تحميل إعدادات الورق: $error');
    }
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      devices
        ..clear()
        ..addAll(await bridge.devices(transport: transportFilter));
      final status = await bridge.connectionStatus(restore: true);
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
      final status = await bridge.connectionStatus(restore: true);
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
    if (connecting) return;
    setState(() => connecting = true);
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
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> _setTransport(String value) async {
    if (transportFilter == value) return;
    setState(() { transportFilter = value; busy = true; });
    try {
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

  Future<void> printShared({bool automatic = false}) async {
    if (printingShare) return;
    if (sharedItems.isEmpty && sharedText.trim().isEmpty) {
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
            await RasterPrint.imageToEscPosAsync(bytes, maxWidth: printWidthDots, alignment: printAlignment),
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

      if (sharedText.trim().isNotEmpty) {
        await bridge.write(
          await RasterPrint.textToEscPos(
            sharedText,
            widthDots: printWidthDots,
            alignment: printAlignment,
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
    switch (device.deviceType) {
      case 'phone': return Icons.smartphone;
      case 'audio': return Icons.headphones;
      case 'printer': return Icons.print;
      case 'computer': return Icons.computer;
      case 'network': return Icons.router;
      default: return Icons.devices_other;
    }
  }

  Widget _printerSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الاتصال بالطابعة',
              style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: Icon(
              Icons.print,
              color: selected == null ? Colors.red : Colors.green,
            ),
            title: Text(selected?.name ?? 'لا توجد جلسة طباعة نشطة'),
            subtitle: Text(
              selected == null
                  ? 'غير متصل بالتطبيق'
                  : selected!.transport == 'usb'
                      ? 'متصل عبر USB'
                      : 'متصل عبر Bluetooth',
            ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(transportFilter),
            initialValue: transportFilter,
            decoration: const InputDecoration(labelText: 'طريقة الاتصال', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'bluetooth', child: Row(children: [Icon(Icons.bluetooth), SizedBox(width: 10), Text('Bluetooth')])),
              DropdownMenuItem(value: 'usb', child: Row(children: [Icon(Icons.usb), SizedBox(width: 10), Text('USB')])),
            ],
            onChanged: busy || connecting ? null : (value) { if (value != null) _setTransport(value); },
          ),
          FilledButton.icon(
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.search),
            label: Text(busy ? 'جارٍ البحث والاستعادة...' : 'البحث واستعادة الاتصال'),
          ),
          ...devices.where((device) => device.transport == transportFilter).map(
            (device) => Card(
              child: ListTile(
                leading: Icon(_deviceIcon(device)),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: TextButton(
                  onPressed: connecting ? null : () => connect(device),
                  child: Text(connecting ? 'جارٍ الاتصال...' : 'اتصال'),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: selected == null
                ? null
                : () => printBytes(EscPos.testPage()),
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
          Text('الطباعة من المشاركة',
              style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'اختر مشاركة ثم XP Printer من أي تطبيق. ينتقل التطبيق إلى هذه الشاشة ويبدأ الطباعة تلقائياً عند توفر اتصال بالطابعة.',
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inbox),
              title: const Text('العناصر المستلمة'),
              subtitle: Text(shareStatus),
            ),
          ),
          if (sharedText.trim().isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('نص مستلم'),
                subtitle: Text(
                  sharedText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: printingShare ||
                    (sharedItems.isEmpty && sharedText.trim().isEmpty)
                ? null
                : () => printShared(),
            icon: printingShare
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(
              printingShare ? 'جارٍ تجهيز الطباعة...' : 'إعادة طباعة العناصر المستلمة',
            ),
          ),
          const SizedBox(height: 10),
          Text('مقاس الورق الحالي: $paperWidthMm مم'),
        ],
      );

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
          Text('إعدادات الطباعة',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('اختر عرض رول الورق المستخدم في طباعة الملفات المشتركة.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('$paperWidthMm:$paperWidthDots'),
            initialValue: paperWidthDots,
            decoration: const InputDecoration(labelText: 'عرض الورق', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 384, child: Text('58 مم — 384 نقطة')),
              DropdownMenuItem(value: 392, child: Text('58 مم — 392 نقطة')),
              DropdownMenuItem(value: 576, child: Text('80 مم — 576 نقطة')),
            ],
            onChanged: (value) { if (value != null) changePaperWidth(value == 576 ? 80 : 58, value); },
          ),
          const SizedBox(height: 12),
          const Text('محاذاة الطباعة'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey(printAlignment),
            initialValue: printAlignment,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: 'تُطبّق على النصوص والصور والملفات المشتركة',
            ),
            items: const [
              DropdownMenuItem(value: 'right', child: Text('يمين')),
              DropdownMenuItem(value: 'center', child: Text('منتصف')),
              DropdownMenuItem(value: 'left', child: Text('يسار')),
            ],
            onChanged: (value) {
              if (value != null) changeAlignment(value);
            },
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
        textDirection: TextDirection.rtl,
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
            destinations: const [
              NavigationDestination(icon: Icon(Icons.share), label: 'المشاركة'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
            ],
          ),
        ),
      );
}
