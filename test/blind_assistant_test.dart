import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/ml/blind_assistant.dart';

void main() {
  group('BlindAssistant Guidance Mode', () {
    late BlindAssistant assistant;

    setUp(() {
      assistant = BlindAssistant();
    });

    test('getStepGuidance() should not ignore Priority 4 objects (like table) if they are near', () async {
      // Pass a raw detection of a 'table' which is Priority 4, near, and center.
      final rawDetections = [
        {
          'detectedClass': 'table', // Priority 4
          'confidenceInClass': 0.8,
          'rect': {'x': 0.2, 'y': 0.2, 'w': 0.6, 'h': 0.6} // Center, near
        }
      ];

      assistant.updateDetections(rawDetections);
      
      final guidance = await assistant.getStepGuidance();
      
      // Since the table is in the center, we should expect "توقف" (stop).
      // The Arabic dictionary might translate 'table' to 'طاولة' or fallback to 'جسم ما' if it's not mapped.
      // But importantly, it should NOT return "الطريق سالك، يمكنك التقدم".
      expect(guidance.contains('الطريق يبدو سالكاً'), false);
      expect(guidance.contains('توقف'), true);
    });

    test('getStepGuidance() should not ignore unknown objects if they are near', () async {
      final rawDetections = [
        {
          'detectedClass': 'unknown', // Priority 4
          'confidenceInClass': 0.8,
          'rect': {'x': 0.01, 'y': 0.2, 'w': 0.6, 'h': 0.6} // Left, near (cx = 0.31)
        }
      ];

      assistant.updateDetections(rawDetections);
      
      final guidance = await assistant.getStepGuidance();
      
      // Left side means we should veer right (حُد لليمين).
      expect(guidance.contains('الطريق يبدو سالكاً'), false);
      expect(guidance.contains('حُد لليمين'), true);
      expect(guidance.contains('جسم ما'), true); // unknown fallback
    });

    test('getStepGuidance() should say path is clear if object is far', () async {
      final rawDetections = [
        {
          'detectedClass': 'table', // Priority 4
          'confidenceInClass': 0.8,
          'rect': {'x': 0.1, 'y': 0.1, 'w': 0.05, 'h': 0.05} // Far
        }
      ];

      assistant.updateDetections(rawDetections);
      
      final guidance = await assistant.getStepGuidance();
      print('Guidance output: $guidance');
      expect(guidance.contains('الطريق يبدو سالكاً'), true);
    });
  });
}
