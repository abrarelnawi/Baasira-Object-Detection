import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';

class GeminiService {
  // TODO: Replace with the actual API Key or load from environment variables
  static const String _apiKey = 'YOUR_API_KEY_HERE';
  static late final GenerativeModel _model;
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _model = GenerativeModel(
      model: 'gemini-flash-latest',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(temperature: 0.1, topK: 1),
    );
    _initialized = true;
  }

  static Future<String> analyzeScene(XFile imageFile) async {
    if (!_initialized) init();
    try {
      final bytes = await imageFile.readAsBytes();
      
      final prompt = TextPart('''
أنت عين اصطناعية لمساعدة شخص كفيف. 
إذا كانت الصورة غير واضحة، مشوشة، أو عبارة عن ألوان عشوائية (مثل شاشة خضراء أو سوداء بالكامل)، يجب أن تقول فقط وبدون أي إضافات: "عذراً، الصورة غير واضحة أو ملتقطة أثناء الحركة، يرجى المحاولة مرة أخرى."
أما إذا كانت الصورة واضحة، فصف المشهد باختصار باللغة العربية، وركز على الأشياء والعقبات أمام المستخدم في جملتين فقط. لا تكتب أي حروف أو أرقام عشوائية أبداً.
''');
      
      final imageParts = [
        DataPart('image/jpeg', bytes),
      ];

      final response = await _model.generateContent([
        Content.multi([prompt, ...imageParts])
      ]);

      return response.text?.replaceAll(RegExp(r'\*'), '') ?? "عذراً، لم أتمكن من تحليل الصورة جيداً.";
    } catch (e) {
      print("Gemini API Error: $e");
      String errorMsg = e.toString().toLowerCase();
      
      if (errorMsg.contains('socket') || errorMsg.contains('network')) {
        return "عذراً، لا يوجد اتصال بالإنترنت.";
      }
      
      // Return the exact error so we can debug it
      return "خطأ في الاتصال: $e";
    }
  }
  static Future<String> chat(String promptText) async {
    if (!_initialized) init();
    try {
      final response = await _model.generateContent([
        Content.text(promptText)
      ]);
      return response.text?.replaceAll(RegExp(r'\*'), '') ?? "لم أتمكن من الإجابة.";
    } catch (e) {
      print("Gemini Chat Error: $e");
      return "عذراً، الذكاء الاصطناعي غير متصل بالإنترنت حالياً.";
    }
  }
}
