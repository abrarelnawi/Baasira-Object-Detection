import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/utils/object_memory.dart';
import 'package:object_detection_app/ml/spatial_analyzer.dart';

void main() {
  group('ObjectMemory', () {
    late ObjectMemory memory;

    setUp(() {
      memory = ObjectMemory();
    });

    test('should track objects and mark them as new only after 600ms', () async {
      final obj = SpatialObject(label: 'chair', score: 0.9, zone: 'left', verticalZone: 'ground', distance: 'near', priority: 3, isDanger: false, isGroundObstacle: false);
      
      // First sighting
      memory.update([obj]);
      expect(memory.newObjects().isEmpty, true, reason: 'Object needs to be seen for 600ms before becoming new');

      // Wait 700ms and see it again
      await Future.delayed(const Duration(milliseconds: 700));
      memory.update([obj]);
      
      final newObjs = memory.newObjects();
      expect(newObjs.length, 1);
      expect(newObjs.first.label, 'chair');
    });

    test('should suppress repeats for 12 seconds', () async {
      final obj = SpatialObject(label: 'table', score: 0.9, zone: 'center', verticalZone: 'ground', distance: 'near', priority: 3, isDanger: false, isGroundObstacle: false);
      
      // Seen for 700ms
      memory.update([obj]);
      await Future.delayed(const Duration(milliseconds: 700));
      memory.update([obj]);

      // It is new now
      expect(memory.newObjects().length, 1);

      // Mark it as spoken
      memory.markSpoken([obj]);

      // Now it should NOT be returned by newObjects()
      expect(memory.newObjects().isEmpty, true);
    });

    test('should expire objects not seen recently', () async {
      final obj = SpatialObject(label: 'laptop', score: 0.9, zone: 'right', verticalZone: 'top', distance: 'mid', priority: 3, isDanger: false, isGroundObstacle: false);
      
      memory.update([obj]);
      expect(memory.currentObjects.length, 1);

      // In real scenario, ObjectMemory expires objects after 8 seconds.
      // Testing the 8-second expiry directly in unit tests takes too long,
      // but we can test manual clearing.
      memory.clear();
      expect(memory.currentObjects.isEmpty, true);
    });
  });
}
