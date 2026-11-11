import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_p323b/main.dart';

void main() {
  testWidgets('XP Printer home screen renders', (tester) async {
    await tester.pumpWidget(const XpApp());

    expect(find.text('XP Printer'), findsOneWidget);
    expect(find.text('الطباعة من المشاركة'), findsOneWidget);
    expect(find.text('اختر مشاركة'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('إعدادات الطباعة'), findsOneWidget);
    expect(find.text('محاذاة الطباعة'), findsOneWidget);
    expect(find.text('يمين'), findsOneWidget);
    expect(find.text('منتصف'), findsOneWidget);
    expect(find.text('يسار'), findsOneWidget);
  });
}
