import 'package:freshly_core/freshly_core.dart';

/// How a booking's state reads to the person doing the job.
///
/// `clientLabel` is written for the customer ("Pro confirmed", "Finding your
/// pro"), which is the wrong voice on the provider's own screen. The states
/// are the same; only the words and the tone of the pill change.
extension PartnerBookingStatus on BookingStatus {
  String get partnerLabel => switch (this) {
        BookingStatus.pendingAuth => 'Awaiting payment',
        BookingStatus.authorized => 'Confirmed',
        BookingStatus.accepted => 'Accepted',
        BookingStatus.enRoute => 'On the way',
        BookingStatus.arrived => 'Arrived',
        BookingStatus.inProgress => 'In progress',
        BookingStatus.completed => 'Paid',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.expired => 'Expired',
        BookingStatus.disputed => 'Under review',
        BookingStatus.draft => 'Draft',
      };

  /// The shared mapping, so a booking's pill is the same colour in both apps.
  FreshlyTone get tone => toneForBooking(this);
}
