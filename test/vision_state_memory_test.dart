import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/utils/vision_state_memory.dart';

void main() {
  group('VisionStateMemory (VisionObject)', () {
    test('VisionObject should initialize correctly', () {
      final obj = VisionObject(
        id: 'car_123',
        label: 'car',
        x: 0.1,
        y: 0.2,
        w: 0.3,
        h: 0.4,
        firstSeen: DateTime.now(),
        lastSeen: DateTime.now(),
      );

      expect(obj.id, 'car_123');
      expect(obj.label, 'car');
      expect(obj.stableFrames, 1);
      expect(obj.area, closeTo(0.12, 0.0001));
    });

    test('VisionObject update() should update position and increment frames', () {
      final obj = VisionObject(
        id: 'person_456',
        label: 'person',
        x: 0.0,
        y: 0.0,
        w: 0.1,
        h: 0.1,
        firstSeen: DateTime.now(),
        lastSeen: DateTime.now(),
      );

      expect(obj.stableFrames, 1);
      
      obj.update(0.2, 0.3, 0.4, 0.5);
      
      expect(obj.x, 0.2);
      expect(obj.y, 0.3);
      expect(obj.w, 0.4);
      expect(obj.h, 0.5);
      expect(obj.stableFrames, 2);
      expect(obj.area, closeTo(0.2, 0.0001));
    });
  });
}
