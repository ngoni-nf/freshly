import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';

void main() {
  group('parseMinor', () {
    test('reads whole and decimal prices without a double', () {
      expect(parseMinor('12'), 1200);
      expect(parseMinor('12.5'), 1250);
      expect(parseMinor('12.35'), 1235);
      expect(parseMinor('0.07'), 7);
      expect(parseMinor('12,50'), 1250);
    });

    test('refuses anything that is not a plain amount', () {
      expect(parseMinor(''), isNull);
      expect(parseMinor('-5'), isNull);
      expect(parseMinor('12.345'), isNull);
      expect(parseMinor('R12'), isNull);
    });

    test('round-trips through the field formatter', () {
      for (final minor in [0, 7, 1235, 120000]) {
        expect(parseMinor(minorToInput(minor)), minor);
      }
    });
  });

  test('applyBps rounds half away from zero like the API', () {
    expect(applyBps(18450, 150), 277); // 276.75
    expect(applyBps(1000, 15), 2); // 1.5
    expect(applyBps(-1000, 15), -2);
    expect(applyBps(0, 150), 0);
  });
}
