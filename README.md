# XP-P323B Printer

تطبيق Flutter مخصص لطابعة Xprinter XP-P323B لطباعة ملصقات المنتجات والفواتير.

الدفعة الأولى تؤسس واجهة عربية RTL، جسر Android Native، اكتشاف Bluetooth وUSB OTG، واستقبال مشاركة Android للصور وPDF والنصوص. أوامر TSPL وESC/POS الحالية أولية للاختبار فقط.

## البناء
ثبّت Flutter stable وAndroid SDK، ثم نفّذ `flutter pub get` و`flutter run`. إذا لم يوجد مجلد Android القياسي فنفّذ `flutter create --platforms=android --org com.xpprinter .`.

## تنبيهات
- Bluetooth يستخدم RFCOMM/SPP ويحتاج اختباراً على نسخة الطابعة الفعلية.
- USB يحتاج هاتفاً يدعم USB Host/OTG وموافقة Android على صلاحية USB.
- دعم العربية الإنتاجي يتطلب تشكيل RTL وتحويل النص إلى صورة حرارية؛ لا يُعتمد إرسال Unicode مباشرة إلى ESC/POS.
- استقبال المشاركة يمرر الملفات إلى التطبيق؛ تحويل PDF والصور إلى بيانات حرارية سيكتمل في مرحلة لاحقة.
