import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';

void main() {
  group('Money', () {
    test('formats South African rand from minor units', () {
      expect(const Money(minor: 18000, currency: 'ZAR').format(), 'R180.00');
    });

    test('formats United States dollars for the Zimbabwe market', () {
      expect(const Money(minor: 1550, currency: 'USD').format(), r'US$15.50');
    });

    test('compacts whole amounts when asked', () {
      expect(const Money(minor: 18000, currency: 'ZAR').format(compact: true), 'R180');
    });
  });

  group('BookingStatus', () {
    test('maps snake_case wire values', () {
      expect(BookingStatus.fromWire('en_route'), BookingStatus.enRoute);
      expect(BookingStatus.fromWire('in_progress'), BookingStatus.inProgress);
    });

    test('knows which states are live and which are terminal', () {
      expect(BookingStatus.enRoute.isLive, isTrue);
      expect(BookingStatus.completed.isTerminal, isTrue);
      expect(BookingStatus.completed.isLive, isFalse);
    });
  });

  group('GridStatus', () {
    test('forces the power filter from stage 4 upward', () {
      GridStatus at(int stage) => GridStatus(
            countryCode: 'ZA', stage: stage, source: 'test',
            nextWindowStart: null, nextWindowEnd: null,
          );
      expect(at(0).forcesPowerFilter, isFalse);
      expect(at(3).forcesPowerFilter, isFalse);
      expect(at(4).forcesPowerFilter, isTrue);
      expect(at(6).forcesPowerFilter, isTrue);
    });
  });

  group('ServiceCategory', () {
    test('round-trips the one wire value that is not the enum name', () {
      expect(ServiceCategory.bodyGrooming.wire, 'body_grooming');
      expect(
          ServiceCategory.fromWire('body_grooming'), ServiceCategory.bodyGrooming);
      // Brows and lashes are now distinct professions, not one merged value.
      expect(ServiceCategory.brows.wire, 'brows');
      expect(ServiceCategory.lashes.wire, 'lashes');
    });
  });
}
