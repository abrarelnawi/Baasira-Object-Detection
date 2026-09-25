import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async'; // for Completer

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;

    await _tts.setLanguage("ar-SA");
    await _tts.setSpeechRate(0.65); // Faster speech rate as requested
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    
    // Critical for preventing overlaps: wait for speech to finish!
    await _tts.awaitSpeakCompletion(true);

    _tts.setCompletionHandler(() {
      print("[TtsService] ✅ Speech completed");
      _isSpeaking = false;
    });

    _tts.setCancelHandler(() {
      print("[TtsService] 🚫 Speech cancelled");
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      print("[TtsService] ❌ TTS error: $msg");
      _isSpeaking = false;
    });

    _initialized = true;
    print("[TtsService] Initialized ✅");
  }

  Future<void> speak(String text, {bool interrupt = false}) async {
    print("[TtsService] ▶ speak() → '$text' (interrupt: $interrupt)");

    if (_isSpeaking && !interrupt) {
      print("[TtsService] 🚫 Ignored speak() because already speaking: '$text'");
      return;
    }

    try {
      await _ensureInit();
      
      if (interrupt) {
        await _tts.stop(); // stop anything playing
      }
      
      _isSpeaking = true;

      // Speak the entire sentence (Native TTS handles internal commas well)
      final completer = Completer<void>();

      _tts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });

      _tts.setErrorHandler((msg) {
        print("[TtsService] ❌ TTS error: $msg");
        if (!completer.isCompleted) completer.complete();
      });

      _tts.setCancelHandler(() {
        print("[TtsService] 🚫 TTS cancelled");
        if (!completer.isCompleted) completer.complete();
      });

      // Use queue mode (QUEUE_ADD) for android to guarantee it doesn't interrupt itself natively
      await _tts.setQueueMode(1); 

      await _tts.speak(text);

      // Wait for the native TTS completer (with a safety timeout)
      await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
        print("[TtsService] ⚠️ TTS timeout reached!");
      });
      
      print("[TtsService] Finished speaking string");
    } catch (e, stack) {
      print("[TtsService] ❌ ERROR: $e");
      print("[TtsService] STACK: $stack");
    } finally {
      // Ensure the state isn't reset until the engine actually stops
      await Future.delayed(const Duration(milliseconds: 500));
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    print("[TtsService] stop()");
    _isSpeaking = false;
    await _tts.stop();
  }

  void dispose() {
    print("[TtsService] dispose()");
    _isSpeaking = false;
    _tts.stop();
  }
}
