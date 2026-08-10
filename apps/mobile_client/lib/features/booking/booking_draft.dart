import 'package:freshly_core/freshly_core.dart';

/// The in-flight booking as the user assembles it. Held in memory only —
/// nothing is reserved and no money moves until checkout.
class BookingDraft {
  BookingDraft({
    required this.providerId,
    required this.providerName,
    required this.services,
    this.venueMode = 'mobile',
    this.bookingType = 'instant',
    this.destination,
    this.destinationAddress,
    this.destinationNotes,
    this.scheduledStart,
    this.promoCode,
    this.quote,
  });

  final String providerId;
  final String providerName;
  final List<ServiceItem> services;
  String venueMode;
  String bookingType;
  GeoPoint? destination;
  String? destinationAddress;
  String? destinationNotes;
  DateTime? scheduledStart;
  String? promoCode;
  PriceQuote? quote;

  int get durationMinutes =>
      services.fold(0, (sum, s) => sum + s.durationMinutes);

  bool get requiresPower => services.any((s) => s.requiresPower);

  bool get isReadyForCheckout =>
      destination != null &&
      destinationAddress != null &&
      (bookingType == 'instant' || scheduledStart != null);

  Map<String, dynamic> toCreatePayload() => {
        'providerId': providerId,
        'serviceIds': services.map((s) => s.id).toList(),
        'bookingType': bookingType,
        'venueMode': venueMode,
        'destination': destination!.toJson(),
        'destinationAddress': destinationAddress,
        if (destinationNotes != null) 'destinationNotes': destinationNotes,
        if (scheduledStart != null)
          'scheduledStart': scheduledStart!.toUtc().toIso8601String(),
        if (promoCode != null) 'promoCode': promoCode,
      };
}
