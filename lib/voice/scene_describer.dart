import 'dart:convert';
import 'package:http/http.dart' as http;
import '../ml/postprocessor.dart';

class SceneDescriber {
  static const String _hermesUrl =
      "https://hermes.ai.unturf.com/v1/chat/completions";
  static const String _model = "adamo1139/Hermes-3-Llama-3.1-8B-FP8-Dynamic";

  static Future<String> describe(List<Detection> detections) async {
    print("[SceneDescriber] describe() — ${detections.length} detections");

    if (detections.isEmpty) {
      print("[SceneDescriber] No detections");
      return "لا أرى شيئاً بوضوح الآن. "
          "يرجى توجيه الكاميرا نحو محيطك.";
    }

    final summary = detections
        .map((d) {
          final pct = (d.score * 100).toStringAsFixed(0);
          return '${d.label} ($pct%)';
        })
        .join(', ');

    print("[SceneDescriber] Detected: $summary");

    final prompt =
        'الكاميرا ترى: $summary. '
        'صِف المشهد في 3 إلى 4 جمل دافئة وطبيعية لمستخدم كفيف باللغة العربية. '
        'اذكر أماكن الأشياء (يسار، يمين، أمام، قريب). '
        'أنهِ القول بـ: هز الهاتف مرتين إذا كان لديك سؤال.';

    try {
      print("[SceneDescriber] Calling Hermes...");

      final response = await http
          .post(
            Uri.parse(_hermesUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer choose-any-value',
            },
            body: jsonEncode({
              "model": _model,
              "temperature": 0.7,
              "max_tokens": 180, // more tokens = richer description
              "messages": [
                {
                  "role": "system",
                  "content":
                      "أنت مساعد صوتي ودود ووصفي يساعد مكفوفاً على "
                      "فهم محيطه. دائماً اذكر المواقع المكانية. أجب باللغة العربية حصراً. "
                      "لا تستخدم تنسيق Markdown أو قوائم. تحدث بشكل طبيعي كأنك تتحدث إلى صديق.",
                },
                {"role": "user", "content": prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30)); // ✅ 30s timeout

      print("[SceneDescriber] HTTP ${response.statusCode}");
      print("[SceneDescriber] Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices']?[0]?['message']?['content']
            ?.toString()
            .trim();
        print("[SceneDescriber] ✅ Description: $text");
        return text ??
            "أرى بعض الأشياء ولكن لا يمكنني وصفها. "
                "هز الهاتف مرتين لسؤالي مباشرة.";
      } else {
        print("[SceneDescriber] ❌ ${response.statusCode}: ${response.body}");
        return "أرى: ${detections.map((d) => d.label).join(', ')}. "
            "هز الهاتف مرتين لسؤالي عن أي شيء.";
      }
    } catch (e, stack) {
      print("[SceneDescriber] ❌ ERROR: $e");
      print("[SceneDescriber] STACK: $stack");
      return "أرى: ${detections.map((d) => d.label).join(', ')}. "
          "هز الهاتف مرتين لسؤالي عن أي شيء.";
    }
  }
}
