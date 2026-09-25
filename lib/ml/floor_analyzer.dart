import 'dart:typed_data';
import 'package:camera/camera.dart';

class FloorAnalyzer {
  // ── Tuning knobs ──────────────────────────────────────────────────────
  // Higher = less sensitive, fewer false positives

  /// Minimum brightness difference between adjacent pixels to count as an edge.
  /// 100 filters out normal floor textures; only real steps/curbs pass.
  static const int _gradientThreshold = 100;

  /// A scan-line is considered a "strong edge line" only if this fraction
  /// of its sampled pixels exceed the gradient threshold.
  /// 0.40 = 40% of the line must be a sharp edge — much stricter.
  static const double _edgePixelRatioThreshold = 0.40;

  /// Minimum number of strong-edge scan-lines needed in the floor ROI
  /// to report a threshold/step.  Must be >= 5 to avoid false positives.
  static const int _minStrongEdgeRows = 5;

  /// Strong-edge lines must be somewhat consecutive (within this many
  /// scan-lines of each other) to count.  Scattered edges = texture, not a step.
  static const int _maxGapBetweenEdgeRows = 3;

  // ── Internal cooldown ─────────────────────────────────────────────────
  /// Ignore detections for this many frames after a positive detection.
  /// At ~15-30 fps this gives about 1–2 seconds of silence.
  static const int _cooldownFrames = 30;
  static int _framesSinceLastDetection = _cooldownFrames; // start ready

  /// Analyzes the bottom part of the camera image to detect strong horizontal
  /// lines that usually indicate thresholds, steps, or curbs.
  static bool detectThreshold(CameraImage image, int sensorOrientation) {
    // Cooldown: skip if we recently detected
    if (_framesSinceLastDetection < _cooldownFrames) {
      _framesSinceLastDetection++;
      return false;
    }

    if (image.format.group != ImageFormatGroup.yuv420) {
      return false;
    }

    final Uint8List yPlane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    // Determine the Region of Interest (bottom 25% of display in world space)
    int startX = 0, endX = width;
    int startY = 0, endY = height;

    if (sensorOrientation == 90) {
      // Floor = left side of raw landscape image (bottom 25%)
      endX = (width * 0.25).toInt();
    } else if (sensorOrientation == 270) {
      startX = (width * 0.75).toInt();
    } else if (sensorOrientation == 0) {
      startY = (height * 0.75).toInt();
    } else if (sensorOrientation == 180) {
      endY = (height * 0.25).toInt();
    }

    // Track which scan-line indices had strong edges
    final List<int> strongEdgeIndices = [];
    int stepSize = 4;

    if (sensorOrientation == 90 || sensorOrientation == 270) {
      int scanIndex = 0;
      for (int x = startX; x < endX; x += stepSize) {
        int edgePixels = 0;
        int sampledPixels = 0;
        for (int y = 1; y < height; y += stepSize) {
          int idx = y * width + x;
          int prevIdx = (y - 1) * width + x;
          if (idx >= yPlane.length || prevIdx >= yPlane.length) continue;

          int currentPixel = yPlane[idx];
          int previousPixel = yPlane[prevIdx];
          sampledPixels++;

          if ((currentPixel - previousPixel).abs() > _gradientThreshold) {
            edgePixels++;
          }
        }

        if (sampledPixels > 0 &&
            edgePixels > sampledPixels * _edgePixelRatioThreshold) {
          strongEdgeIndices.add(scanIndex);
        }
        scanIndex++;
      }
    } else {
      int scanIndex = 0;
      for (int y = startY; y < endY; y += stepSize) {
        int edgePixels = 0;
        int sampledPixels = 0;
        for (int x = 1; x < width; x += stepSize) {
          int idx = y * width + x;
          int prevIdx = y * width + (x - 1);
          if (idx >= yPlane.length || prevIdx >= yPlane.length) continue;

          int currentPixel = yPlane[idx];
          int previousPixel = yPlane[prevIdx];
          sampledPixels++;

          if ((currentPixel - previousPixel).abs() > _gradientThreshold) {
            edgePixels++;
          }
        }

        if (sampledPixels > 0 &&
            edgePixels > sampledPixels * _edgePixelRatioThreshold) {
          strongEdgeIndices.add(scanIndex);
        }
        scanIndex++;
      }
    }

    // Need enough strong-edge lines
    if (strongEdgeIndices.length < _minStrongEdgeRows) return false;

    // Check that the strong-edge lines are mostly consecutive (a real step
    // produces a cluster of adjacent strong-edge lines, not scattered ones).
    int consecutiveCount = 1;
    int maxConsecutive = 1;
    for (int i = 1; i < strongEdgeIndices.length; i++) {
      if (strongEdgeIndices[i] - strongEdgeIndices[i - 1] <= _maxGapBetweenEdgeRows) {
        consecutiveCount++;
        if (consecutiveCount > maxConsecutive) {
          maxConsecutive = consecutiveCount;
        }
      } else {
        consecutiveCount = 1;
      }
    }

    final bool detected = maxConsecutive >= _minStrongEdgeRows;

    if (detected) {
      _framesSinceLastDetection = 0; // start cooldown
    }

    return detected;
  }
}
