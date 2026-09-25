import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OfflineTextRecognizer {
  // Use Latin script since Arabic is not natively supported in this plugin version.
  // We will detect the English back-side of the Libyan Dinar instead!
  static final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  static bool _isProcessing = false;
  static DateTime _lastReadTime = DateTime.now().subtract(const Duration(seconds: 10));

  static Future<String?> processFrame(CameraImage image, int sensorOrientation) async {
    if (_isProcessing) return null;
    
    // Limit reading frequency to avoid spamming the user
    if (DateTime.now().difference(_lastReadTime).inSeconds < 6) {
      return null;
    }

    _isProcessing = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
      final InputImageFormat inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      String text = recognizedText.text.trim();
      if (text.isNotEmpty) {
        // --- 🇱🇾 Libyan Currency Detection Heuristic (English Back-side) ---
        final lowerText = text.toLowerCase();
        bool isLibyanMoney = lowerText.contains('libya') || 
                             lowerText.contains('central bank') || 
                             lowerText.contains('dinar') ||
                             lowerText.contains('dinars');
                             
        if (isLibyanMoney) {
          String value = "";
          if (lowerText.contains('50') || lowerText.contains('fifty')) value = "خمسون";
          else if (lowerText.contains('20') || lowerText.contains('twenty')) value = "عشرون";
          else if (lowerText.contains('10') || lowerText.contains('ten')) value = "عشرة";
          else if (lowerText.contains('5') || lowerText.contains('five')) value = "خمسة";
          else if (lowerText.contains('1') || lowerText.contains('one')) value = "واحد";
          
          if (value.isNotEmpty) {
            _lastReadTime = DateTime.now();
            return "ورقة نقدية ليبية بقيمة $value دينار";
          }
        }
        
        // General text fallback (only return if it has substantial content)
        if (text.length > 4 || RegExp(r'\d').hasMatch(text)) {
          _lastReadTime = DateTime.now();
          return text.replaceAll('\n', ' ');
        }
      }
    } catch (e) {
      print("OCR Error: $e");
    } finally {
      _isProcessing = false;
    }
    return null;
  }
}
