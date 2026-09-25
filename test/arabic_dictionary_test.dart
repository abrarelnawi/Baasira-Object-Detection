import 'package:flutter_test/flutter_test.dart';
import 'package:object_detection_app/ml/arabic_dictionary.dart';

void main() {
  group('ArabicDictionary', () {
    test('isKnown() should return true for known words and false for unknown', () {
      expect(ArabicDictionary.isKnown('car'), true);
      expect(ArabicDictionary.isKnown('person'), true);
      expect(ArabicDictionary.isKnown('table'), true);
      expect(ArabicDictionary.isKnown('chair'), true);
      expect(ArabicDictionary.isKnown('unknown_random_string'), false);
      expect(ArabicDictionary.isKnown('alien spaceship'), false);
    });

    test('getExact() should return mapped arabic word or "جسم ما" for unknown words', () {
      expect(ArabicDictionary.getExact('car'), 'سيارة');
      expect(ArabicDictionary.getExact('person'), 'شخص');
      expect(ArabicDictionary.getExact('unknown_string_123'), 'جسم ما');
    });
  });
}
