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
  bool busy = false;
  bool printingShare = false;

  @override
  void initState() {
    super.initState();
    shareSub = bridge.shares.listen((message) {
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
      });
    }, onError: (Object error) {
      if (mounted) toast('تعذر استقبال المشاركة: $error');
    });
    refresh();
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

  Future<void> refresh() async {
    setState(() => busy = true);
    try {
      devices
        ..clear()
        ..addAll(await bridge.devices());
      if (mounted) setState(() {});
    } catch (error) {
      toast('تعذر البحث: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect(PrinterDevice device) async {
    try {
      await bridge.connect(device);
      if (mounted) setState(() => selected = device);
      toast('تم الاتصال: ${device.name}');
    } catch (error) {
      toast('فشل الاتصال: $error');
    }
  }

  Future<void> printBytes(List<int> bytes) async {
    if (selected == null) {
      setState(() => tab = 2);
      toast('اختر الطابعة أولاً');
      return;
    }
    try {
      await bridge.write(bytes);
      toast('تم إرسال أمر الطباعة');
    } catch (error) {
      toast('خطأ في الطباعة: $error');
    }
  }

  Future<void> printShared() async {
    if (selected == null) {
      setState(() => tab = 2);
      toast('اختر الطابعة أولاً');
      return;
    }
    if (sharedItems.isEmpty && sharedText.trim().isEmpty) {
      toast('لا توجد ملفات أو نصوص مستلمة للطباعة');
      return;
    }

    setState(() => printingShare = true);
    var printed = 0;
    var unsupportedPdf = false;
    try {
      for (final item in sharedItems) {
        final mime = (item['mimeType']?.toString() ?? '').toLowerCase();
        final path = item['path']?.toString() ?? '';
        if (mime.startsWith('image/')) {
          if (path.isEmpty) throw StateError('مسار الصورة المستلمة غير موجود');
          final bytes = await File(path).readAsBytes();
          await bridge.write(RasterPrint.imageToEscPos(bytes));
          printed++;
        } else if (mime == 'application/pdf' || path.toLowerCase().endsWith('.pdf')) {
          unsupportedPdf = true;
        }
      }

      if (sharedItems.isEmpty && sharedText.trim().isNotEmpty) {
        await bridge.write(await RasterPrint.textToEscPos(sharedText));
        printed++;
      }

      if (printed > 0) {
        toast('تم إرسال $printed عنصر للطباعة');
      }
      if (unsupportedPdf) {
        toast('ملف PDF مستلم؛ تحويل صفحات PDF للطباعة سيكون في المرحلة التالية');
      }
      if (printed == 0 && !unsupportedPdf) {
        toast('نوع الملف غير مدعوم حالياً؛ استخدم صورة أو نصاً');
      }
    } catch (error) {
      toast('تعذر طباعة المشاركة: $error');
    } finally {
      if (mounted) setState(() => printingShare = false);
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
                    onPressed: () => printBytes(
                      Tspl.label(
                        name: product.text,
                        price: price.text,
                        barcode: barcode.text,
                      ),
                    ),
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة ملصق تجريبي'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'أوامر TSPL أولية؛ تشكيل العربية ومعايرة الملصق في المرحلة التالية.',
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
                    onPressed: () => printBytes(
                      EscPos.invoice(
                        number: invoice.text,
                        item: product.text,
                        price: price.text,
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('طباعة فاتورة اختبار'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'النسخة الإنتاجية ستستخدم تشكيل RTL وتحويل الفاتورة إلى صورة حرارية.',
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('الاتصال بالطابعة',
                      style: Theme.of(context).textTheme.titleLarge),
                  ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(selected?.name ?? 'لا توجد طابعة متصلة'),
                    subtitle: Text(
                      selected?.transport == 'usb'
                          ? 'USB'
                          : selected == null
                              ? 'غير متصل'
                              : 'Bluetooth',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : refresh,
                    icon: const Icon(Icons.search),
                    label: Text(busy ? 'جارٍ البحث...' : 'البحث عن الأجهزة'),
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
                    'USB يتطلب OTG وUSB Host. Bluetooth يحتاج إقران الطابعة أولاً من إعدادات الهاتف.',
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('الطباعة من المشاركة',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Text(
                    'من أي تطبيق اختر مشاركة ثم XP Printer. يستقبل التطبيق PDF والصور والنصوص.',
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
                            selected == null ||
                            (sharedItems.isEmpty && sharedText.trim().isEmpty)
                        ? null
                        : printShared,
                    icon: printingShare
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(
                      printingShare ? 'جارٍ تجهيز الطباعة...' : 'طباعة العناصر المستلمة',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'الصور والنصوص تُحوّل إلى صورة حرارية أحادية اللون بعرض 576 نقطة. ملفات PDF تُستقبل حالياً، وسيضاف تحويل صفحاتها في مرحلة لاحقة.',
                  ),
                ],
              ),
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
            ],
          ),
        ),
      );
}
