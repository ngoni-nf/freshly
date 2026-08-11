import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';

void main() {
  group('DispatchOffer', () {
    DispatchOffer offerExpiringIn(Duration d) => DispatchOffer(
          offerId: 'o1',
          bookingId: 'b1',
          reference: 'FRS-ABC123',
          serviceNames: const ['Skin fade'],
          distanceKm: 2.4,
          etaMinutes: 11,
          payout: const Money(minor: 15750, currency: 'ZAR'),
          destinationAddress: 'Sandton',
          expiresAt: DateTime.now().add(d),
          clientRating: 4.8,
        );

    test('reports time remaining from the server expiry, not a local timer',
        () {
      final offer = offerExpiringIn(const Duration(seconds: 45));
      expect(offer.remaining.inSeconds, closeTo(45, 1));
    });

    test('reports a negative duration once it has lapsed', () {
      final offer = offerExpiringIn(const Duration(seconds: -5));
      expect(offer.remaining.isNegative, isTrue);
    });

    test('exposes the payout as money, never a bare number', () {
      expect(offerExpiringIn(const Duration(seconds: 60)).payout.format(),
          'R157.50');
    });
  });

  group('formatters', () {
    test('formats short distances in metres', () {
      expect(formatDistance(0.4), '400 m');
      expect(formatDistance(2.45), '2.5 km');
    });

    test('formats an eta a provider can read at a glance', () {
      expect(formatEta(0), 'Arriving');
      expect(formatEta(11), '11 min');
      expect(formatEta(75), '1h 15m');
      expect(formatEta(null), '--');
    });

    test('masks a counterparty number', () {
      expect(maskPhone('+27821112222'), '+278•••22');
    });
  });
}
