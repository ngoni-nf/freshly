import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_client/app/notifications.dart';

void main() {
  group('push deep links', () {
    test('a chat push opens the thread', () {
      expect(pushDestination({'type': 'chat', 'bookingId': 'b1'}),
          '/track/b1/chat');
    });

    test('a support reply opens that ticket', () {
      expect(pushDestination({'type': 'support.reply', 'ticketId': 't9'}),
          '/support?ticket=t9');
      expect(pushDestination({'type': 'support.reply'}), '/support');
    });

    test('a cancellation opens the booking, not a map', () {
      expect(pushDestination({'type': 'booking_cancelled', 'bookingId': 'b1'}),
          '/bookings/b1');
    });

    test('anything else about a booking opens tracking', () {
      expect(pushDestination({'type': 'booking.updated', 'bookingId': 'b1'}),
          '/track/b1');
      expect(pushDestination({'bookingId': 'b1'}), '/track/b1');
    });

    test('a push with nothing to open goes nowhere', () {
      expect(pushDestination({}), isNull);
      expect(pushDestination({'type': 'chat'}), isNull);
    });
  });
}
