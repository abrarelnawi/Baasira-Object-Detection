import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/voice/scene_describer.dart';

void main() {
  group('SceneDescriber', () {
    test('describe() should return fallback string for empty detections without calling HTTP', () async {
      final result = await SceneDescriber.describe([]);
      expect(result.contains('لا أرى شيئاً بوضوح الآن'), isTrue);
    });
  });
}
