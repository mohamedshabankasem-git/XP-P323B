import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_p323b/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const printerChannel = MethodChannel('xp_p323b/printer');
  const shareChannel = 'xp_p323b/share';

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(printerChannel, (call) async {
      switch (call.method) {
        case 'discoverDevices':
          return <dynamic>[];
        case 'restoreConnection':
        case 'connectionStatus':
          return <String, dynamic>{'connected': false};
        case 'getSettings':
          return <String, dynamic>{
            'paperWidthMm': 80,
            'printAlignment': 'right',
          };
        case 'setPrintAlignment':
        case 'setPaperWidth':
          return true;
        default:
          return null;
      }
    });
    messenger.setMockMessageHandler(
      shareChannel,
      (message) async =>
          const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(printerChannel, null);
    messenger.setMockMessageHandler(shareChannel, null);
  });

  testWidgets('XP Printer home screen and print settings render',
      (tester) async {
    await tester.pumpWidget(const XpApp());
    await tester.pumpAndSettle();

    expect(find.text('XP Printer'), findsOneWidget);
    expect(find.text('الطباعة من المشاركة'), findsOneWidget);
    expect(
      find.textContaining('اختر مشاركة ثم XP Printer'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('إعدادات الطباعة'), findsOneWidget);
    expect(find.text('محاذاة الطباعة'), findsOneWidget);
    // A saved non-default alignment must appear after asynchronous settings load.
    expect(find.text('يمين'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('right')));
    await tester.pumpAndSettle();

    // The selected value remains visible behind the open popup, so the
    // selected label can appear twice while the menu is open.
    expect(find.text('يمين'), findsWidgets);
    expect(find.text('يسار'), findsOneWidget);
    expect(find.text('منتصف'), findsOneWidget);

    await tester.tap(find.text('يسار').last);
    await tester.pumpAndSettle();
    expect(find.text('يسار'), findsOneWidget);
  });
}
