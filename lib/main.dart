import 'dart:async';
import 'package:flutter/material.dart';
import 'printer/printer_bridge.dart';
import 'printer/tspl.dart';
import 'printer/escpos.dart';

void main() => runApp(const XpApp());
class XpApp extends StatelessWidget {
  const XpApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'XP Printer',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1769aa))),
    home: const Home(),
  );
}
class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  final bridge = PrinterBridge();
  final product = TextEditingController(text: 'منتج تجريبي');
  final price = TextEditingController(text: '25.00');
  final barcode = TextEditingController(text: '6221234567890');
  final invoice = TextEditingController(text: '1001');
  final devices = <PrinterDevice>[];
  PrinterDevice? selected;
  StreamSubscription? shareSub;
  String shareStatus = 'لم يتم استقبال مشاركة بعد';
  int tab = 0;
  bool busy = false;
  @override void initState() {
    super.initState();
    shareSub = bridge.shares.listen((m) {
      final items = (m['items'] as List? ?? []);
      setState(() => shareStatus = items.map((e) => e['name']).join('، '));
    });
    refresh();
  }
  @override void dispose() {
    shareSub?.cancel(); product.dispose(); price.dispose(); barcode.dispose(); invoice.dispose(); super.dispose();
  }
  void toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> refresh() async {
    setState(() => busy = true);
    try { devices..clear()..addAll(await bridge.devices()); setState(() {}); }
    catch (e) { toast('تعذر البحث: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> connect(PrinterDevice d) async {
    try { await bridge.connect(d); setState(() => selected = d); toast('تم الاتصال: ' + d.name); }
    catch (e) { toast('فشل الاتصال: $e'); }
  }
  Future<void> printBytes(List<int> bytes) async {
    if (selected == null) { setState(() => tab = 2); toast('اختر الطابعة أولاً'); return; }
    try { await bridge.write(bytes); toast('تم إرسال أمر الطباعة'); }
    catch (e) { toast('خطأ في الطباعة: $e'); }
  }
  Widget field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
  );
  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('XP Printer'), centerTitle: true,
        actions: [Padding(padding: const EdgeInsets.all(16), child: Icon(Icons.circle, size: 11, color: selected == null ? Colors.red : Colors.green))]),
      body: IndexedStack(index: tab, children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          Text('ملصق منتج', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12), field(product, 'اسم المنتج'), field(price, 'السعر'), field(barcode, 'الباركود'),
          FilledButton.icon(onPressed: () => printBytes(Tspl.label(name: product.text, price: price.text, barcode: barcode.text)),
            icon: const Icon(Icons.print), label: const Text('طباعة ملصق تجريبي')),
          const SizedBox(height: 12), const Text('أوامر TSPL أولية؛ تشكيل العربية ومعايرة الملصق في المرحلة التالية.'),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          Text('الفواتير', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12), field(invoice, 'رقم الفاتورة'), field(product, 'الصنف'), field(price, 'السعر'),
          FilledButton.icon(onPressed: () => printBytes(EscPos.invoice(number: invoice.text, item: product.text, price: price.text)),
            icon: const Icon(Icons.receipt_long), label: const Text('طباعة فاتورة اختبار')),
          const SizedBox(height: 12), const Text('النسخة الإنتاجية ستستخدم تشكيل RTL وتحويل الفاتورة إلى صورة حرارية.'),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          Text('الاتصال بالطابعة', style: Theme.of(context).textTheme.titleLarge),
          ListTile(leading: const Icon(Icons.print), title: Text(selected?.name ?? 'لا توجد طابعة متصلة'),
            subtitle: Text(selected?.transport == 'usb' ? 'USB' : selected == null ? 'غير متصل' : 'Bluetooth')),
          FilledButton.icon(onPressed: busy ? null : refresh, icon: const Icon(Icons.search),
            label: Text(busy ? 'جارٍ البحث...' : 'البحث عن الأجهزة')),
          ...devices.map((d) => Card(child: ListTile(
            leading: Icon(d.transport == 'usb' ? Icons.usb : Icons.bluetooth),
            title: Text(d.name), subtitle: Text(d.address),
            trailing: TextButton(onPressed: () => connect(d), child: const Text('اتصال'))))),
          OutlinedButton(onPressed: selected == null ? null : () => printBytes(EscPos.testPage()),
            child: const Text('طباعة صفحة اختبار')),
          const Text('USB يتطلب OTG وUSB Host. Bluetooth يحتاج إقران الطابعة أولاً من إعدادات الهاتف.'),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          Text('الطباعة من المشاركة', style: Theme.of(context).textTheme.titleLarge),
          const Text('من أي تطبيق اختر مشاركة ثم XP Printer. يستقبل التطبيق PDF والصور والنصوص.'),
          const SizedBox(height: 12), Card(child: ListTile(leading: const Icon(Icons.inbox),
            title: const Text('العناصر المستلمة'), subtitle: Text(shareStatus))),
          const Text('المرحلة التالية: تحويل الملفات المستلمة إلى صورة حرارية ثم طباعتها مباشرة.'),
        ]),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sell_outlined), label: 'الملصقات'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'الفواتير'),
          NavigationDestination(icon: Icon(Icons.print_outlined), label: 'الطابعة'),
          NavigationDestination(icon: Icon(Icons.share), label: 'المشاركة'),
        ]),
    ),
  );
}
