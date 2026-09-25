import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:mocktail/mocktail.dart';
import 'package:object_detection_app/api/gemini_service.dart';

class MockXFile extends Mock implements XFile {}

void main() {
  group('GeminiService', () {
    test('init() should initialize without crashing', () {
      expect(() => GeminiService.init(), returnsNormally);
    });

    test('analyzeScene() with invalid file should return error message', () async {
      final mockFile = MockXFile();
      when(() => mockFile.readAsBytes()).thenThrow(Exception('Simulated File Error'));

      final result = await GeminiService.analyzeScene(mockFile);
      expect(result, contains('عذراً، حدث خطأ'));
    });
  });
}
