import 'spatial_analyzer.dart';
import '../utils/object_memory.dart';
import 'assistant_mode.dart';
import 'arabic_dictionary.dart';
import '../api/gemini_service.dart';

  const Map<String, String> _arZones = {
    'left': 'يسارك',
    'center': 'أمامك',
    'right': 'يمينك',
  };

  const Map<String, String> _arVerticalZones = {
    'ground': 'على الأرض',
    'middle': 'بمستوى الوسط',
    'top': 'بالأعلى',
  };

  const Map<String, String> _arDistances = {
    'near': 'قريب جداً',
    'mid': 'على بعد متوسط',
    'far': 'بعيد',
  };

class BlindAssistant {
  AssistantMode mode = AssistantMode.navigate;
  final ObjectMemory _memory = ObjectMemory();
  List<SpatialObject> _currentObjects = [];

  void updateDetections(List<dynamic> rawDetections) {
    _currentObjects = SpatialAnalyzer.analyze(rawDetections);
    _memory.update(_currentObjects);
  }

  bool get hasDanger => SpatialAnalyzer.hasDanger(_currentObjects);
  List<SpatialObject> get dangerObjects => SpatialAnalyzer.dangerObjects(_currentObjects);

  // Auto-announce new objects in Arabic — batch mode (up to 5 objects in one sentence)
  String? getNewObjectsToAnnounceInArabic(bool guidanceActive) {
    final objects = _memory.newObjects();
    if (objects.isEmpty) return null;

    // Take up to 2 objects, sorted by urgency
    final batch = objects.take(2).toList();

    // Check if we have any near or mid objects in the batch
    bool hasCloseObjects = batch.any((o) => o.distance != 'far');

    // Filter: in normal mode, skip unknown objects
    final filtered = <SpatialObject>[];
    for (var obj in batch) {
      // If there are close objects, skip the far ones to avoid clutter
      if (hasCloseObjects && obj.distance == 'far') {
        _memory.markSpoken([obj]);
        continue;
      }

      bool isKnown = ArabicDictionary.isKnown(obj.label);
      if (!isKnown && !guidanceActive) {
        _memory.markSpoken([obj]);
        continue;
      }
      filtered.add(obj);
    }

    if (filtered.isEmpty) return null;

    // Mark all as spoken
    _memory.markSpoken(filtered);

    // If guidance is active, focus on the most urgent object to provide clear direction
    if (guidanceActive && mode == AssistantMode.navigate) {
      final obj = filtered.first;
      final label = ArabicDictionary.getExact(obj.label);
      final loc = SpatialAnalyzer.zoneToArabic(obj.zone, obj.verticalZone, isGroundObstacle: obj.isGroundObstacle);
      
      String sentence = '$label $loc';
      
      if (obj.distance == 'near' || obj.isDanger || obj.isGroundObstacle) {
        String guidance = SpatialAnalyzer.guidanceForZone(obj.zone, obj.verticalZone);
        if (guidance.isNotEmpty) {
          sentence = 'انتبه، $label $loc، $guidance';
        }
      }
      return sentence;
    }

    // Normal mode: Build very short direct phrases for up to 2 objects
    final List<String> phrases = [];
    for (var obj in filtered) {
      final label = ArabicDictionary.getExact(obj.label);
      final loc = SpatialAnalyzer.zoneToArabic(obj.zone, obj.verticalZone, isGroundObstacle: obj.isGroundObstacle);
      phrases.add('$label $loc');
    }

    return phrases.join('، ').trim();
  }

  // Describe current scene intelligently using AI
  Future<String> describeScene() async {
    final objects = _currentObjects;
    if (objects.isEmpty) return 'لا أرى شيئاً واضحاً أمامي الآن.';

    List<String> parts = [];
    for (var o in objects) {
      String label = ArabicDictionary.getExact(o.label);
      String loc = SpatialAnalyzer.zoneToArabic(o.zone, o.verticalZone, isGroundObstacle: o.isGroundObstacle);
      parts.add('$label $loc');
    }
    
    final localDesc = 'أرى حالياً: ' + parts.join('، و ');
    
    String guidanceInstruction = mode == AssistantMode.navigate 
        ? "أعطِ توجيهات حركية للمستخدم لتجنب العقبات بناءً على موقع الأشياء (مثل توقف فوراً، أو اتجه لليمين/لليسار)." 
        : "اكتفِ فقط بوصف المشهد وقراءة أسماء الأشياء وأماكنها بطريقة طبيعية. ممنوع منعاً باتاً إعطاء أي أوامر حركية أو توجيهات (لا تقل توقف، لا تقل اتجه).";
        
    final prompt = "أنت عين اصطناعية لمكفوف. الكاميرا ترى الآن: $localDesc. \n"
                   "$guidanceInstruction \n"
                   "أجب باختصار في جملة أو جملتين باللغة العربية وبدون تنسيق Markdown.";
                   
    try {
      final aiResponse = await GeminiService.chat(prompt);
      // Fallback if Gemini gives error text
      if (aiResponse.contains("عذراً")) return localDesc;
      return aiResponse;
    } catch (e) {
      return localDesc;
    }
  }

  // Danger-specific alert locally without internet
  Future<String> dangerAlert() async {
    final dangers = dangerObjects;
    if (dangers.isEmpty) return '';

    List<String> warnings = [];
    for (var o in dangers) {
      String label = ArabicDictionary.getExact(o.label);
      String loc = SpatialAnalyzer.zoneToArabic(o.zone, o.verticalZone, isGroundObstacle: o.isGroundObstacle);
      
      String act = '';
      if (mode == AssistantMode.navigate) {
        act = SpatialAnalyzer.guidanceForZone(o.zone, o.verticalZone);
        if (act.isNotEmpty) act = '$act. ';
      }

      warnings.add('احذر، $label $loc. $act'.trim());
    }

    return warnings.join(' ');
  }

  // Respond intelligently using AI
  Future<String> respondToUser(String userSpeech) async {
    final localDesc = await describeScene();
    final prompt = 'أنت مساعد صوتي ذكي وعطوف لمكفوف. المستخدم يرى أمامه عبر الكاميرا: $localDesc. \n'
        'المستخدم يقول لك الآن: "$userSpeech". \n'
        'أجب باختصار (جملة أو جملتين) وبطريقة طبيعية وودودة باللغة العربية. '
        'لا تستخدم رموز ماركداون.';
    return await GeminiService.chat(prompt);
  }

  Future<String> getStepGuidance() async {
    if (hasDanger) return await dangerAlert();
    
    final obstacles = _currentObjects.where((o) => o.distance != 'far').toList();
    if (obstacles.isNotEmpty) {
      final o = obstacles.first;
      String label = ArabicDictionary.getExact(o.label);
      String loc = SpatialAnalyzer.zoneToArabic(o.zone, o.verticalZone, isGroundObstacle: o.isGroundObstacle);
      String act = SpatialAnalyzer.guidanceForZone(o.zone, o.verticalZone);

      return 'يوجد $label $loc، $act.';
    }

    return 'الطريق يبدو سالكاً، يمكنك التقدم بحذر.';
  }

  void setMode(AssistantMode m) {
    mode = m;
    _memory.clear();
  }

  void clearHistory() {
    _memory.clear();
  }
}
