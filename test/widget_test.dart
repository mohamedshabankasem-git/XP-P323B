import 'package:flutter_test/flutter_test.dart';
import 'package:xp_p323b/main.dart';

void main() {
  testWidgets('XP Printer home screen renders', (tester) async {
    await tester.pumpWidget(const XpApp());
    expect(find.text('XP Printer'), findsOneWidget);
    expect(find.text('الطباعة من المشاركة'), findsOneWidget);
    expect(find.text('إعدادات الطباعة'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
  });
}
