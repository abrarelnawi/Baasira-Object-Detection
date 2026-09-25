import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../ml/tflite_service.dart';
import '../ml/blind_assistant.dart';
import '../voice/speech_service.dart';
import '../voice/tts_service.dart';
import '../utils/shake_detector.dart';
import '../ml/assistant_mode.dart';
import '../ui/overlay_painter.dart';
import '../api/gemini_service.dart';
import '../ml/text_recognizer.dart';
import '../ml/floor_analyzer.dart';

enum ViewState { idle, describing, speaking, listening, thinking, danger }

class CameraView extends StatefulWidget {
  final CameraController controller;
  final TFLiteService service;

  const CameraView({
    super.key,
    required this.controller,
    required this.service,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  List<dynamic>? _recognitions;

  bool _isBusy = false;
  int _frameCount = 0;
  static const int _skipFrames = 3;

  final BlindAssistant _assistant = BlindAssistant();
  final SpeechService _stt = SpeechService();
  final TtsService _tts = TtsService();
  final ShakeDetector _shake = ShakeDetector();

  ViewState _state = ViewState.idle;
  String _statusText = 'جاري البدء...';
  bool _loopActive = false;

  // Danger: track last warned to avoid spam
  String _lastDangerKey = '';
  DateTime _lastDangerTime = DateTime(2000);

  // Auto-announce cooldown (0.5 seconds between announcements)
  DateTime _lastAnnounceTime = DateTime(2000);
  static  final Duration _announceCooldown = const Duration(milliseconds: 500);
  int _unknownObjectCount = 0;

  DateTime _lastThresholdTime = DateTime(2000);

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Step guidance timer
  Timer? _stepTimer;
  bool _stepModeActive = false;

  // Camera sensor orientation (90 for most rear cameras)
  int get _sensorOrientation => widget.controller.description.sensorOrientation;

  @override
  void initState() {
    super.initState();

    // Keep the screen on while the app is active (critical for blind users)
    WakelockPlus.enable();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnim = Tween(
      begin: 1.0,
      end: 1.22,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _stt.init().then((_) {
      _shake.start(_onDoubleShake);
      Future.delayed(const Duration(seconds: 2), _describeScene);
    });

    widget.controller.startImageStream(_onFrame);
  }

  // ─── Camera loop ─────────────────────────────────────────────────────────

  void _onFrame(CameraImage image) async {
    _frameCount++;
    if (_frameCount % _skipFrames != 0) return;
    
    // OCR Processing: runs every frame it can, independent of model busy state
    final text = await OfflineTextRecognizer.processFrame(image, _sensorOrientation);
    if (text != null && mounted) {
      if (!_loopActive && _state == ViewState.idle) {
        // Automatically read short text out loud if idle
        _tts.speak("نص: $text");
      }
    }

    // Floor Analyzer for thresholds
    if (FloorAnalyzer.detectThreshold(image, _sensorOrientation)) {
      final now = DateTime.now();
      if (now.difference(_lastThresholdTime) > const Duration(seconds: 8)) {
        _lastThresholdTime = now;
        _checkThresholdDanger();
      }
    }

    if (_isBusy) return;
    _runModel(image);
  }

  /// Transform raw detection rects from sensor space to portrait display space
  List<dynamic> _transformDetections(List<dynamic> rawResults) {
    final int orientation = _sensorOrientation;
    if (orientation == 0) return rawResults;

    return rawResults.map((r) {
      final rect = r['rect'];
      if (rect == null) return r;

      final double rx = (rect['x'] ?? 0).toDouble();
      final double ry = (rect['y'] ?? 0).toDouble();
      final double rw = (rect['w'] ?? 0).toDouble();
      final double rh = (rect['h'] ?? 0).toDouble();

      double px, py, pw, ph;

      if (orientation == 90) {
        // Most common for rear cameras
        // Raw landscape → Portrait: rotate 90° CCW
        px = ry;
        py = 1.0 - rx - rw;
        pw = rh;
        ph = rw;
      } else if (orientation == 270) {
        // Some front cameras
        px = 1.0 - ry - rh;
        py = rx;
        pw = rh;
        ph = rw;
      } else {
        // 180°
        px = 1.0 - rx - rw;
        py = 1.0 - ry - rh;
        pw = rw;
        ph = rh;
      }

      // Clamp to valid range
      px = px.clamp(0.0, 1.0);
      py = py.clamp(0.0, 1.0);
      pw = pw.clamp(0.0, 1.0 - px);
      ph = ph.clamp(0.0, 1.0 - py);

      return {
        ...Map<String, dynamic>.from(r),
        'rect': {'x': px, 'y': py, 'w': pw, 'h': ph},
      };
    }).toList();
  }

  Future<void> _runModel(CameraImage image) async {
    _isBusy = true;
    try {
      final results = await widget.service.detect(image);
      if (!mounted) return;

      if (results != null) {
        // Transform coordinates from sensor space to portrait display space
        final transformed = _transformDetections(results);
        setState(() => _recognitions = transformed);

        _assistant.updateDetections(transformed);

        // Check for new danger
        if (_assistant.hasDanger) {
          _checkDanger();
        } else {
          _checkAutoAnnounce();
        }
      } else {
        setState(() => _recognitions = results);
      }
    } catch (e) {
      print('Detection error: $e');
    } finally {
      _isBusy = false;
    }
  }

  // ─── Auto-Announce ───────────────────────────────────────────────────────

  void _checkAutoAnnounce() async {
    // Only auto-announce if completely idle
    if (_state != ViewState.idle || _loopActive) return;

    // Enforce 1.5 second cooldown between announcements
    final now = DateTime.now();
    if (now.difference(_lastAnnounceTime) < _announceCooldown) return;

    final newObjectsText = _assistant.getNewObjectsToAnnounceInArabic(_stepModeActive);
    if (newObjectsText != null && newObjectsText.isNotEmpty) {
      if (newObjectsText.contains('جسم ما')) {
        _unknownObjectCount++;
      } else {
        _unknownObjectCount = 0;
      }

      if (_unknownObjectCount >= 3) {
        _unknownObjectCount = 0;
        try {
          final result = await InternetAddress.lookup('google.com');
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            _loopActive = true;
            await _tts.speak("عقبات متعددة غير مألوفة، أقوم بالفحص العميق.", interrupt: true);
            await Future.delayed(const Duration(milliseconds: 2500));
            _loopActive = false; // allow deep scan to start
            _deepScan();
            return;
          }
        } on SocketException catch (_) {
          // No internet, ignore rescue
        }
      }

      _loopActive = true;
      _lastAnnounceTime = DateTime.now();
      _setUiState(ViewState.speaking, newObjectsText);
      await _tts.speak(newObjectsText);
      // Wait 1.5 seconds after speech finishes before allowing next announcement
      await Future.delayed(_announceCooldown);
      if (mounted && _state == ViewState.speaking) {
        _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
      }
      _loopActive = false;
    }
  }

  // ─── Danger detection ────────────────────────────────────────────────────

  bool _isSpeakingDanger = false;

  void _checkDanger() async {
    if (_isSpeakingDanger) return;

    final dangers = _assistant.dangerObjects;
    if (dangers.isEmpty) return;

    final key = dangers.map((d) => '${d.label}_${d.zone}').join(',');
    final now = DateTime.now();

    if (key == _lastDangerKey && now.difference(_lastDangerTime).inSeconds < 15)
      return;

    _lastDangerKey = key;
    _lastDangerTime = now;

    print('[CameraView] 🚨 Danger: $key');

    _isSpeakingDanger = true;
    
    // Interrupt current speech removed
    _loopActive = false;

    // Long vibration for danger
    final canVibrate = await Vibration.hasVibrator() ?? false;
    if (canVibrate) {
      Vibration.vibrate(
        pattern: [0, 500, 200, 500],
        intensities: [0, 255, 0, 255],
      );
    }

    _setUiState(ViewState.danger, '🚨 تم اكتشاف خطر!');

    final alert = await _assistant.dangerAlert();

    // Speak danger twice
    _setUiState(ViewState.speaking, alert);
    await _tts.speak(alert, interrupt: false);
    await Future.delayed(const Duration(milliseconds: 600));
    await _tts.speak(alert, interrupt: false); // repeat for safety

    _isSpeakingDanger = false;
    _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
  }

  void _checkThresholdDanger() async {
    // 1. Double pulse vibration
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 150, 100, 150]);
    }
    
    // 2. Immediate speech interruption (Disabled as per user request to not cut off speech)
    _tts.speak("انتبه، عتبة أو رصيف أمامك", interrupt: false);

    if (mounted) {
      _setUiState(ViewState.danger, 'عتبة أمامك!');
      
      // Reset UI state after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _state == ViewState.danger) {
          _setUiState(ViewState.idle, 'جاري المسح...');
        }
      });
    }
  }

  // ─── Describe + speak ────────────────────────────────────────────────────

  Future<void> _describeScene() async {
    if (_loopActive) return;
    _loopActive = true;

    _setUiState(ViewState.describing, '👁 جاري تحليل المشهد...');
    final desc = await _assistant.describeScene();

    // Short vibration: new description
    final canVibrate = await Vibration.hasVibrator() ?? false;
    if (canVibrate) Vibration.vibrate(duration: 80);

    _setUiState(ViewState.speaking, desc);
    await _tts.speak(desc, interrupt: true);

    _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
    _loopActive = false;
  }

  Future<void> _deepScan() async {
    _loopActive = true;
    await _tts.stop();
    await _stt.stopListening();

    _setUiState(ViewState.describing, '👁 جاري الفحص العميق...');
    try {
      await widget.controller.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 200));
      final XFile photo = await widget.controller.takePicture();
      widget.controller.startImageStream(_onFrame);
      final desc = await GeminiService.analyzeScene(photo);
      
      final canVibrate = await Vibration.hasVibrator() ?? false;
      if (canVibrate) Vibration.vibrate(duration: 80);

      _setUiState(ViewState.speaking, desc);
      await _tts.speak(desc, interrupt: true);
    } catch (e) {
      _setUiState(ViewState.speaking, "تعذر الفحص العميق. تأكد من الإنترنت.");
      await _tts.speak("تعذر الفحص العميق.", interrupt: true);
    } finally {
      if (!widget.controller.value.isStreamingImages) {
        widget.controller.startImageStream(_onFrame);
      }
      _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
      _loopActive = false;
    }
  }

  // ─── Shake → listen ──────────────────────────────────────────────────────

  void _onDoubleShake() {
    print('[CameraView] Double shake!');
    if (_state == ViewState.speaking) _tts.stop();
    if (_loopActive) {
      _loopActive = false;
      Future.delayed(const Duration(milliseconds: 300), _startListening);
    } else {
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (_loopActive) return;
    _loopActive = true;

    // Short vibrate on listen start
    final canVibrate = await Vibration.hasVibrator() ?? false;
    if (canVibrate) Vibration.vibrate(duration: 60);

    _setUiState(ViewState.listening, '🎙 جاري الاستماع...');

    bool gotResult = false;

    await _stt.startListening((transcript) async {
      if (gotResult) return;
      gotResult = true;

      print('[CameraView] Heard: "$transcript"');

      if (transcript.trim().isEmpty) {
        await _tts.speak("لم أفهم ذلك. هز الهاتف مرتين للمحاولة.", interrupt: true);
        _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
        _loopActive = false;
        return;
      }

      _setUiState(ViewState.thinking, '💭 "${transcript}"');
      final reply = await _assistant.respondToUser(transcript);

      _setUiState(ViewState.speaking, reply);
      await _tts.speak(reply, interrupt: true);

      _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
      _loopActive = false;
    });

    // Timeout
    await Future.delayed(const Duration(seconds: 12));
    if (_state == ViewState.listening && mounted) {
      await _stt.stopListening();
      await _tts.speak("لم أسمع شيئاً. هز الهاتف مرتين للمحاولة.", interrupt: true);
      _setUiState(ViewState.idle, 'هز الهاتف مرتين للسؤال');
      _loopActive = false;
    }
  }

  // ─── Step guidance mode ──────────────────────────────────────────────────

  void _toggleStepMode() {
    setState(() => _stepModeActive = !_stepModeActive);

    if (_stepModeActive) {
      _tts.speak('تم تفعيل وضع التوجيه خطوة بخطوة.', interrupt: true);
      _stepTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_loopActive) return;
        final step = await _assistant.getStepGuidance();
        _setUiState(ViewState.speaking, step);
        await _tts.speak(step);
        if (_state == ViewState.speaking) {
          _setUiState(ViewState.idle, 'التوجيه المستمر نشط');
        }
      });
    } else {
      _stepTimer?.cancel();
      _tts.speak('تم إيقاف التوجيه.');
    }
  }

  // ─── Mode selector ───────────────────────────────────────────────────────

  void _cycleMode() {
    final modes = AssistantMode.values;
    final next = modes[(_assistant.mode.index + 1) % modes.length];
    _assistant.setMode(next);
    _tts.speak('وضع ${next.label}.', interrupt: true);
    setState(() {});
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _setUiState(ViewState s, String text) {
    if (!mounted) return;
    setState(() {
      _state = s;
      _statusText = text;
    });
  }

  Future<void> _onDescribeTap() async {
    await _tts.stop();
    await _stt.stopListening();
    _loopActive = false;
    _assistant.clearHistory();
    await Future.delayed(const Duration(milliseconds: 200));
    await _describeScene();
  }

  @override
  void dispose() {
    // Release the screen wake lock when leaving the app
    WakelockPlus.disable();
    _pulseCtrl.dispose();
    _stepTimer?.cancel();
    _shake.stop();
    _tts.dispose();
    _stt.dispose();
    widget.controller.stopImageStream();
    widget.service.close();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool active = _state != ViewState.idle;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onLongPress: _deepScan,
          child: CameraPreview(widget.controller),
        ),

        if (_recognitions != null && _recognitions!.isNotEmpty)
          OverlayPainter(_recognitions!),

        // Border glow
        if (active)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _stateColor().withOpacity(0.6),
                    width: 4,
                  ),
                ),
              ),
            ),
          ),

        // Status card
        Positioned(
          top: 52,
          left: 12,
          right: 12,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(_statusText),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _state == ViewState.danger
                    ? Colors.red.withOpacity(0.92)
                    : Colors.black.withOpacity(0.82),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _stateColor().withOpacity(0.7),
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Transform.scale(
                      scale:
                          (_state == ViewState.listening ||
                              _state == ViewState.danger)
                          ? _pulseAnim.value
                          : 1.0,
                      child: child,
                    ),
                    child: Icon(_stateIcon(), color: _stateColor(), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Mode badge
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: _cycleMode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _assistant.mode.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 44,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Step mode toggle
              _ControlButton(
                icon: _stepModeActive
                    ? Icons.directions_walk
                    : Icons.directions_walk_outlined,
                label: _stepModeActive ? 'توجيه نشط' : 'توجيه',
                color: _stepModeActive ? Colors.greenAccent : Colors.white,
                onTap: _toggleStepMode,
                pulse: _stepModeActive,
                pulseAnim: _pulseAnim,
              ),

              // Main describe button
              GestureDetector(
                onTap: _onDescribeTap,
                onLongPress: _deepScan,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: active ? _pulseAnim.value : 1.0,
                    child: child,
                  ),
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.75),
                      border: Border.all(color: _stateColor(), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: _stateColor().withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Icon(_stateIcon(), color: _stateColor(), size: 34),
                  ),
                ),
              ),

              // Mode cycle button
              _ControlButton(
                icon: Icons.tune,
                label: 'الوضع',
                color: Colors.white,
                onTap: _cycleMode,
                pulse: false,
                pulseAnim: _pulseAnim,
              ),
            ],
          ),
        ),

        // Shake hint
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Text(
            _state == ViewState.idle ? '📳 هز الهاتف مرتين للسؤال' : _stateLabel(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _stateColor().withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              shadows: [const Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ),
      ],
    );
  }

  Color _stateColor() => switch (_state) {
    ViewState.danger => Colors.redAccent,
    ViewState.listening => Colors.redAccent,
    ViewState.speaking => Colors.greenAccent,
    ViewState.thinking => Colors.amberAccent,
    ViewState.describing => Colors.blueAccent,
    ViewState.idle => Colors.white,
  };

  IconData _stateIcon() => switch (_state) {
    ViewState.danger => Icons.warning_amber_rounded,
    ViewState.listening => Icons.mic,
    ViewState.speaking => Icons.volume_up,
    ViewState.thinking => Icons.psychology,
    ViewState.describing => Icons.visibility,
    ViewState.idle => Icons.visibility_outlined,
  };

  String _stateLabel() => switch (_state) {
    ViewState.danger => 'خطر',
    ViewState.listening => 'استماع',
    ViewState.speaking => 'تحدث',
    ViewState.thinking => 'تفكير',
    ViewState.describing => 'وصف',
    ViewState.idle => 'اضغط للوصف',
  };
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool pulse;
  final Animation<double> pulseAnim;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.pulse,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.65),
              border: Border.all(color: color, width: 1.8),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.3), blurRadius: 10),
              ],
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [const Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
    return pulse ? ScaleTransition(scale: pulseAnim, child: btn) : btn;
  }
}
