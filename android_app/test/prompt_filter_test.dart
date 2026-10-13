import 'package:flutter_test/flutter_test.dart';
import 'package:kira_void/phone_images.dart';

void main() {
  test('blocks minors, allows adults', () {
    for (final p in ['teen girl', 'a 12-year-old', '15 yo', 'aged 16', 'ей 16 лет', 'школьница', 'furry cub', 'babyfur']) {
      expect(() => checkPrompt(p), throwsA(isA<String>()), reason: p);
    }
    for (final p in ['adult woman, 25 years old', '30yo man', 'aged 40', 'женщина 30 лет', 'sunset', 'anthro wolf, adult, furry']) {
      expect(() => checkPrompt(p), returnsNormally, reason: p);
    }
  });
}
