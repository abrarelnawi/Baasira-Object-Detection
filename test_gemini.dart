import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  final apiKey = 'YOUR_API_KEY_HERE';
  final model = GenerativeModel(
    model: 'gemini-flash-latest',
    apiKey: apiKey,
  );

  try {
    final response = await model.generateContent([Content.text('مرحبا، هل أنت متصل؟')]);
    print('Response: ' + (response.text ?? 'empty'));
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
