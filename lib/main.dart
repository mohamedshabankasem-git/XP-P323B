import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'printer/printer_bridge.dart';
import 'printer/tspl.dart';
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
  final product = TextEditingController(text: 'منتج تجريبي');
  final price = TextEditingController(text: '25.00');
  final barcode = TextEditingController(text: '6221234567890');
  final invoice = TextEditingController(text: '1001');
  final devices = <PrinterDevice>[];
  final sharedItems = <Map<String, dynamic>>[];
  PrinterDevice? selected;
  StreamSubscription? shareSub;
  String sharedText = '';
  String shareStatus = 'لم يتم استقبال مشاركة بعد';
  int tab = 0;
  int paperWidthMm = 80;
  bool busy = false;
  bool printingShare = false;

  int get printWidthDots => paperWidthMm == 58 ? 384 : 576;

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
    product.dispose();
    price.dispose();
    barcode.dispose();
    invoice.dispose();
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
      tab = 3;
    });

    // The share shortcut is intended to print immediately when a printer is
    // connected. If reconnection is needed, printShared attempts it first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) printShared(automatic: true);
    });
  }

  Future<void> _loadSettings() async {
    try {
      final width = await bridge.paperWidthMm();
      if (mounted) setState(() => paperWidthMm = width);
    } catch (error) {
      toast('تعذر تحميل إعدادات الورق: $error');
    }
  }

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      devices
        ..clear()
        ..addAll(await bridge.devices());
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
    }
  }

  Future<void> printBytes(List<int> bytes) async {
    if (!await ensureConnected()) {
      setState(() => tab = 2);
      toast('الطابعة غير متصلة بالتطبيق. اختر الطابعة واضغط اتصال.');
      return;
    }
    try {
      await bridge.write(bytes);
      toast('تم إرسال أمر الطباعة');
    } catch (error) {
      setState(() => selected = null);
      toast('فشل إرسال الطباعة: $error');
    }
  }

  Future<void> printLabel() async {
    try {
      final bytes = await Tspl.labelRaster(
        name: product.text,
        price: price.text,
        barcode: barcode.text,
      );
      await printBytes(bytes);
    } catch (error) {
      toast('تعذر تجهيز الملصق: $error');
    }
  }

  Future<void> printInvoice() async {
    final text = [
      'فاتورة رقم: ${invoice.text}',
      '------------------------------',
      'الصنف: ${product.text}',
      'السعر: ${price.text}',
      '------------------------------',
      'شكراً لزيارتكم',
    ].join('\n');
    try {
      await printBytes(
        await RasterPrint.textToEscPos(
          text,
          fontSize: 24,
          widthDots: printWidthDots,
        ),
      );
    } catch (error) {
      toast('تعذر تجهيز الفاتورة: $error');
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
              ? 'تم استقبال المشاركة، لكن لا يوجد اتصال طباعة نشط. افتح شاشة الطابعة واتصل بها ثم أعد المشاركة.'
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
            RasterPrint.imageToEscPos(bytes, maxWidth: printWidthDots),
          );
          printed++;
        } else if (mime == 'application/pdf' ||
            path.toLowerCase().endsWith('.pdf')) {
          final pages = await bridge.renderPdf(
            path,
            widthDots: printWidthDots,
          );
          if (pages.isEmpty) {
            throw StateError('ملف PDF لا يحتوي على صفحات قابلة للطباعة');
          }
          for (final pagePath in pages) {
            final bytes = await File(pagePath).readAsBytes();
            await bridge.write(
              RasterPrint.imageToEscPos(bytes, maxWidth: printWidthDots),
            );
            printed++;
          }
        }
      }

      if (sharedText.trim().isNotEmpty) {
        await bridge.write(
          await RasterPrint.textToEscPos(
            sharedText,
            widthDots: printWidthDots,
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

  Future<void> changePaperWidth(int width) async {
    try {
      await bridge.setPaperWidthMm(width);
      if (mounted) setState(() => paperWidthMm = width);
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

  Widget _printerPage() => ListView(
        padding: const EdgeInsets.all(16),
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
          FilledButton.icon(
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.search),
            label: Text(busy ? 'جارٍ البحث والاستعادة...' : 'البحث واستعادة الاتصال'),
          ),
          ...devices.map(
            (device) => Card(
              child: ListTile(
                leading: Icon(
                  device.transport == 'usb'
                      ? Icons.usb
                      : Icons.bluetooth,
                ),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: TextButton(
                  onPressed: () => connect(device),
                  child: const Text('اتصال'),
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

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('إعدادات الطباعة',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('اختر عرض رول الورق المستخدم في طباعة الفواتير والملفات المشتركة.'),
          const SizedBox(height: 12),
          RadioGroup<int>(
            groupValue: paperWidthMm,
            onChanged: (value) {
              if (value != null) changePaperWidth(value);
            },
            child: const Column(
              children: [
                RadioListTile<int>(
                  value: 58,
                  title: Text('58 مم'),
                  subtitle: Text('عرض طباعة 384 نقطة'),
                ),
                RadioListTile<int>(
                  value: 80,
                  title: Text('80 مم'),
                  subtitle: Text('حد أقصى للطباعة 576 نقطة (72 مم فعلياً)'),
                ),
              ],
            ),
          ),
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
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('ملصق منتج',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  field(product, 'اسم المنتج'),
                  field(price, 'السعر'),
                  field(barcode, 'الباركود'),
                  FilledButton.icon(
                    onPressed: printLabel,
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة ملصق تجريبي'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'اسم المنتج والسعر يُرسمان كصورة عربية عبر Flutter ثم يطبعان بأمر TSPL BITMAP، والباركود بأمر TSPL.',
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('الفواتير',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  field(invoice, 'رقم الفاتورة'),
                  field(product, 'الصنف'),
                  field(price, 'السعر'),
                  FilledButton.icon(
                    onPressed: printInvoice,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('طباعة فاتورة اختبار'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الفاتورة تُرسم كنص عربي RTL إلى صورة حرارية، مع احترام عرض الورق المحدد من الإعدادات.',
                  ),
                ],
              ),
              _printerPage(),
              _sharePage(),
              _settingsPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.sell_outlined),
                label: 'الملصقات',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long),
                label: 'الفواتير',
              ),
              NavigationDestination(
                icon: Icon(Icons.print_outlined),
                label: 'الطابعة',
              ),
              NavigationDestination(
                icon: Icon(Icons.share),
                label: 'المشاركة',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'الإعدادات',
              ),
            ],
          ),
        ),
      );
}
