import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // محاكاة (Mocking) للقنوات الخاصة بالهاردوير لمنع الأخطاء في بيئة الاختبار
    final List<String> channels = [
      'plugins.flutter.io/camera',
      'tflite',
      'plugin.csdcorp.com/speech_to_text',
      'flutter_tts',
      'vibration'
    ];

    for (var channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (MethodCall methodCall) async {
        if (methodCall.method == 'availableCameras') return [];
        return null;
      });
    }
  });

  testWidgets('App UI smoke test', (WidgetTester tester) async {
    // بناء التطبيق
    await tester.pumpWidget(const MyApp());
    
    // التأكد من أن التطبيق يعمل ويظهر شاشة التحميل الأولية بدون انهيار
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
