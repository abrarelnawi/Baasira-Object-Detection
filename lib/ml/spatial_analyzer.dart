class SpatialObject {
  final String label;
  final double score;
  final String zone; // left / center / right
  final String verticalZone; // ground / middle / top
  final String distance; // near / mid / far
  final int priority; // 1=critical 2=important 3=neutral 4=ignore
  final bool isDanger;
  final bool isGroundObstacle;

  const SpatialObject({
    required this.label,
    required this.score,
    required this.zone,
    required this.verticalZone,
    required this.distance,
    required this.priority,
    required this.isDanger,
    required this.isGroundObstacle,
  });

  double get urgencyScore {
    double distMult = distance == 'near' ? 3.0 : (distance == 'mid' ? 1.5 : 0.5);
    return score * (5 - priority) * (isDanger ? 3 : 1) * (isGroundObstacle ? 1.5 : 1) * distMult;
  }

  @override
  String toString() => '$label ($zone, $verticalZone, $distance)';
}

class SpatialAnalyzer {
  // Priority 1 = critical danger
  static const _critical = {
    'car',
    'motorcycle',
    'bicycle',
    'truck',
    'bus',
    'train',
    'knife',
    'scissors',
    'fire hydrant',
    'skateboard',
  };

  // Priority 2 = important
  static const _important = {
    'person',
    'dog',
    'cat',
    'horse',
    'cow',
    'traffic light',
    'stop sign',
    'parking meter',
    'bench',
    'suitcase',
    'backpack',
    'umbrella',
    'handbag',
    'sports ball',
  };

  // Priority 3 = neutral
  static const _neutral = {
    'chair',
    'couch',
    'dining table',
    'bed',
    'toilet',
    'sink',
    'refrigerator',
    'oven',
    'microwave',
    'toaster',
    'tv',
    'laptop',
    'cup',
    'bottle',
    'bowl',
    'potted plant',
    'cell phone',
  };

  // Priority 4 = ignore unless very close
  static const _ignore = {
    'vase',
    'clock',
    'book',
    'remote',
    'keyboard',
    'mouse',
    'teddy bear',
    'hair drier',
    'toothbrush',
  };

  // Objects that are typically ground-level obstacles for a blind user
  static const _groundObstacles = {
    'bicycle',
    'motorcycle',
    'skateboard',
    'suitcase',
    'backpack',
    'handbag',
    'sports ball',
    'dog',
    'cat',
    'bench',
    'chair',
    'fire hydrant',
    'potted plant',
    'bottle',
    'bowl',
    'cup',
  };

  // Objects that are inherently at ground/eye level and should NEVER be
  // described as "بالأعلى" (above). When these appear at the top of the
  // frame, they are simply far away, not overhead.
  static const _inherentlyGroundLevel = {
    'person',
    'dog',
    'cat',
    'horse',
    'cow',
    'car',
    'motorcycle',
    'bicycle',
    'truck',
    'bus',
    'train',
    'chair',
    'couch',
    'bench',
    'dining table',
    'bed',
    'toilet',
    'sink',
    'refrigerator',
    'oven',
    'suitcase',
    'backpack',
    'handbag',
    'fire hydrant',
    'parking meter',
    'potted plant',
    'skateboard',
    'sports ball',
  };

  static List<SpatialObject> analyze(List<dynamic> rawDetections) {
    final List<SpatialObject> result = [];

    for (final r in rawDetections) {
      final label = (r['detectedClass'] ?? 'unknown').toString().toLowerCase();
      final score = (r['confidenceInClass'] ?? 0).toDouble();
      final x = (r['rect']?['x'] ?? 0.5).toDouble();
      final y = (r['rect']?['y'] ?? 0.5).toDouble();
      final w = (r['rect']?['w'] ?? 0.1).toDouble();
      final h = (r['rect']?['h'] ?? 0.1).toDouble();

      // Allow unknown labels to proceed (will be spoken as 'جسم ما' if guidance is active)

      final priority = _getPriority(label);

      final zone = _getZone(x + w / 2);
      final distance = _getDistance(w, h);
      var verticalZone = _getVerticalZone(y + h / 2, y + h, w * h, label);
      final isDanger = priority == 1;

      // Ground obstacle: only if it is explicitly in the _groundObstacles list
      final isGround = _groundObstacles.contains(label);

      result.add(
        SpatialObject(
          label: label,
          score: score,
          zone: zone,
          verticalZone: verticalZone,
          distance: distance,
          priority: priority,
          isDanger: isDanger,
          isGroundObstacle: isGround,
        ),
      );
    }

    // Sort by urgency: ground obstacles and danger first, then priority, then score
    result.sort((a, b) => b.urgencyScore.compareTo(a.urgencyScore));
    return result;
  }

  static String _getZone(double cx) {
    // Coordinates are already transformed to portrait display space
    if (cx < 0.33) return 'left';
    if (cx < 0.66) return 'center';
    return 'right';
  }

  static String _getVerticalZone(double cy, double bottomEdge, double area, String label) {
    // ground = lower 40% of screen (obstacles at foot level)
    // middle = default (not mentioned in speech)
    // top    = only for genuinely overhead objects (signs, awnings, etc.)

    if (cy > 0.60 || bottomEdge > 0.75) return 'ground';

    // "Top" requires ALL of these conditions:
    // 1. Center is in the upper 20% of the frame (stricter than before)
    // 2. Object is NOT an inherently ground-level object (person, chair, car...)
    // 3. Object must be reasonably large (area > 0.03) — tiny objects at top
    //    are just far-away things, not overhead obstacles
    if (cy < 0.20 &&
        !_inherentlyGroundLevel.contains(label) &&
        area > 0.03) {
      return 'top';
    }

    return 'middle';
  }

  static String _getDistance(double w, double h) {
    final area = w * h;
    if (area > 0.25) return 'near';
    if (area > 0.07) return 'mid';
    return 'far';
  }

  /// Returns a natural Arabic description of the zone.
  /// Only mentions "على الأرض" for actual ground obstacles (bags, bottles, etc.)
  static String zoneToArabic(String zone, String verticalZone, {bool isGroundObstacle = false}) {
    String horizontal;
    if (zone == 'left') {
      horizontal = 'على يسارك';
    } else if (zone == 'right') {
      horizontal = 'على يمينك';
    } else {
      horizontal = 'أمامك';
    }

    // Only say "على الأرض" for things you can actually trip over
    if (verticalZone == 'ground' && isGroundObstacle) {
      return '$horizontal على الأرض';
    } else if (verticalZone == 'top') {
      return '$horizontal بالأعلى';
    }
    return horizontal;
  }

  /// Returns avoidance guidance for a given zone
  static String guidanceForZone(String zone, String verticalZone) {
    // If the object is not directly in front of the user, no steering is needed.
    if (zone != 'center') {
      return ''; 
    }

    if (verticalZone == 'ground') {
      return 'توقف، عقبة أمامك';
    }
    if (verticalZone == 'top') {
      return 'انحنِ قليلاً';
    }
    
    // middle zone
    return 'توقف';
  }

  static int _getPriority(String label) {
    if (_critical.any((k) => label.contains(k))) return 1;
    if (_important.any((k) => label.contains(k))) return 2;
    if (_neutral.any((k) => label.contains(k))) return 3;
    return 4;
  }

  static bool hasDanger(List<SpatialObject> objects) =>
      objects.any((o) => o.isDanger && o.distance != 'far');

  static bool hasGroundObstacle(List<SpatialObject> objects) =>
      objects.any((o) => o.isGroundObstacle && o.distance != 'far');

  static List<SpatialObject> dangerObjects(List<SpatialObject> objects) =>
      objects.where((o) => o.isDanger && o.distance != 'far').toList();

  static List<SpatialObject> groundObstacles(List<SpatialObject> objects) =>
      objects.where((o) => o.isGroundObstacle && o.distance != 'far').toList();
}

