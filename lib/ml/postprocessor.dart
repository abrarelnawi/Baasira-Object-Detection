import 'labels.dart';

class Detection {
  final String label;
  final double score;
  final double x;
  final double y;
  final double w;
  final double h;

  const Detection({
    required this.label,
    required this.score,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  @override
  String toString() =>
      'Detection(label: $label, score: ${(score * 100).toStringAsFixed(1)}%, '
      'x: $x, y: $y, w: $w, h: $h)';
}

class PostProcessor {
  static const double _confidenceThreshold = 0.60;

  // Labels that are parts of a person and should be merged into "person"
  static const _personParts = {
    'clothing',
    'footwear',
    'human face',
    'human head',
    'human body',
    'human hand',
    'human arm',
    'human leg',
    'human foot',
    'human eye',
    'human ear',
    'human nose',
    'human mouth',
    'human hair',
    'human beard',
    'man',
    'woman',
    'boy',
    'girl',
    'jeans',
    'dress',
    'shirt',
    'coat',
    'jacket',
    'suit',
    'shorts',
    'trousers',
    'skirt',
    'miniskirt',
    'swimwear',
    'sports uniform',
    'boot',
    'sandal',
    'high heels',
    'glasses',
    'sunglasses',
    'hat',
    'tie',
    'scarf',
    'glove',
    'belt',
    'necklace',
    'earrings',
    'fashion accessory',
    'brassiere',
    'sock',
    'cowboy hat',
    'fedora',
    'sun hat',
    'sombrero',
  };

  static List<Detection> decode(Map<String, dynamic> output) {
    final boxes = output["boxes"][0] as List;
    final classes = output["classes"][0] as List;
    final scores = output["scores"][0] as List;
    final count = (output["count"][0] as num).toInt();

    final List<Detection> results = [];

    for (int i = 0; i < count; i++) {
      final double score = (scores[i] as num).toDouble();

      // Skip detections below confidence threshold
      if (score < _confidenceThreshold) continue;

      final box = boxes[i] as List;
      final classId = (classes[i] as num).toInt();

      final double yMin = (box[0] as num).toDouble();
      final double xMin = (box[1] as num).toDouble();
      final double yMax = (box[2] as num).toDouble();
      final double xMax = (box[3] as num).toDouble();

      results.add(
        Detection(
          label: Labels.get(classId),
          score: score,
          x: xMin,
          y: yMin,
          w: xMax - xMin,
          h: yMax - yMin,
        ),
      );
    }

    // Merge person-part detections into "person"
    final merged = _mergePersonParts(results);

    // Sort by confidence descending (highest confidence first)
    merged.sort((a, b) => b.score.compareTo(a.score));

    return merged;
  }

  /// Merges person-part detections (clothing, footwear, body parts, etc.)
  /// into a single "person" detection using the bounding box that covers
  /// all overlapping parts.
  static List<Detection> _mergePersonParts(List<Detection> detections) {
    final List<Detection> nonPersonParts = [];
    final List<Detection> personParts = [];

    for (final d in detections) {
      final lower = d.label.toLowerCase();
      if (_personParts.contains(lower)) {
        personParts.add(d);
      } else if (lower == 'person') {
        // Keep actual "person" detections as-is
        personParts.add(d);
      } else {
        nonPersonParts.add(d);
      }
    }

    if (personParts.isEmpty) return detections;

    // Group overlapping person-parts into clusters
    final List<List<Detection>> clusters = [];
    final used = <int>{};

    for (int i = 0; i < personParts.length; i++) {
      if (used.contains(i)) continue;
      final cluster = [personParts[i]];
      used.add(i);

      for (int j = i + 1; j < personParts.length; j++) {
        if (used.contains(j)) continue;
        // Check if any detection in the cluster overlaps with j
        if (cluster.any((c) => _overlaps(c, personParts[j]))) {
          cluster.add(personParts[j]);
          used.add(j);
        }
      }
      clusters.add(cluster);
    }

    // Convert each cluster into a single "person" detection
    final List<Detection> merged = [];
    for (final cluster in clusters) {
      double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      double bestScore = 0.0;

      for (final d in cluster) {
        if (d.x < minX) minX = d.x;
        if (d.y < minY) minY = d.y;
        if (d.x + d.w > maxX) maxX = d.x + d.w;
        if (d.y + d.h > maxY) maxY = d.y + d.h;
        if (d.score > bestScore) bestScore = d.score;
      }

      merged.add(Detection(
        label: 'person',
        score: bestScore,
        x: minX,
        y: minY,
        w: maxX - minX,
        h: maxY - minY,
      ));
    }

    return [...nonPersonParts, ...merged];
  }

  /// Check if two detections overlap significantly (IoU > 0.15 or one contains the other)
  static bool _overlaps(Detection a, Detection b) {
    final ax1 = a.x, ay1 = a.y, ax2 = a.x + a.w, ay2 = a.y + a.h;
    final bx1 = b.x, by1 = b.y, bx2 = b.x + b.w, by2 = b.y + b.h;

    final ix1 = ax1 > bx1 ? ax1 : bx1;
    final iy1 = ay1 > by1 ? ay1 : by1;
    final ix2 = ax2 < bx2 ? ax2 : bx2;
    final iy2 = ay2 < by2 ? ay2 : by2;

    if (ix1 >= ix2 || iy1 >= iy2) return false;

    final intersection = (ix2 - ix1) * (iy2 - iy1);
    final areaA = a.w * a.h;
    final areaB = b.w * b.h;
    final smaller = areaA < areaB ? areaA : areaB;

    // Overlap if intersection covers > 15% of the smaller box
    return intersection / smaller > 0.15;
  }
}

