import '../util/money.dart';

enum CountryCode { za, zw }

/// One value per provider specialization, matching service_category_enum.
///
/// Brows and lashes are separate because they are separate professions with
/// separate training and, for permanent makeup, separate licensing. Braiding
/// and locs stay separate because customers search for them separately.
enum ServiceCategory {
  barber,
  beard,
  scalp,
  hair,
  braiding,
  locs,
  extensions,
  color,
  nails,
  makeup,
  lashes,
  brows,
  aesthetics,
  bodyGrooming,
  massage;

  String get wire => switch (this) {
        ServiceCategory.bodyGrooming => 'body_grooming',
        _ => name,
      };

  String get label => switch (this) {
        ServiceCategory.barber => 'Barber',
        ServiceCategory.beard => 'Beard',
        ServiceCategory.scalp => 'Scalp & Hair Loss',
        ServiceCategory.hair => 'Hair',
        ServiceCategory.braiding => 'Braiding',
        ServiceCategory.locs => 'Locs',
        ServiceCategory.extensions => 'Weaves & Wigs',
        ServiceCategory.color => 'Colour & Chemical',
        ServiceCategory.nails => 'Nails',
        ServiceCategory.makeup => 'Makeup',
        ServiceCategory.lashes => 'Lashes',
        ServiceCategory.brows => 'Brows',
        ServiceCategory.aesthetics => 'Skincare',
        ServiceCategory.bodyGrooming => 'Waxing & Hair Removal',
        ServiceCategory.massage => 'Massage',
      };

  static ServiceCategory fromWire(String value) => switch (value) {
        'body_grooming' => ServiceCategory.bodyGrooming,
        _ => ServiceCategory.values.firstWhere((c) => c.name == value,
            orElse: () => ServiceCategory.barber),
      };
}

enum BookingStatus {
  draft,
  pendingAuth,
  authorized,
  accepted,
  enRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
  expired,
  disputed;

  static BookingStatus fromWire(String v) => switch (v) {
        'pending_auth' => BookingStatus.pendingAuth,
        'en_route' => BookingStatus.enRoute,
        'in_progress' => BookingStatus.inProgress,
        _ => BookingStatus.values
            .firstWhere((s) => s.name == v, orElse: () => BookingStatus.draft),
      };

  /// Copy shown to the client on the tracking screen.
  String get clientLabel => switch (this) {
        BookingStatus.pendingAuth => 'Confirming payment',
        BookingStatus.authorized => 'Finding your pro',
        BookingStatus.accepted => 'Pro confirmed',
        BookingStatus.enRoute => 'On the way',
        BookingStatus.arrived => 'Arrived',
        BookingStatus.inProgress => 'In progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.expired => 'No pro available',
        BookingStatus.disputed => 'Under review',
        BookingStatus.draft => 'Draft',
      };

  bool get isLive => const {
        BookingStatus.authorized,
        BookingStatus.accepted,
        BookingStatus.enRoute,
        BookingStatus.arrived,
        BookingStatus.inProgress,
      }.contains(this);

  bool get isTerminal => const {
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.expired,
      }.contains(this);
}

enum PowerBackup {
  generator,
  inverter,
  batteryClippers,
  portableLights,
  solar;

  String get label => switch (this) {
        PowerBackup.generator => 'Generator',
        PowerBackup.inverter => 'Inverter',
        PowerBackup.batteryClippers => 'Battery clippers',
        PowerBackup.portableLights => 'Portable lights',
        PowerBackup.solar => 'Solar',
      };

  String get wire => switch (this) {
        PowerBackup.batteryClippers => 'battery_clippers',
        PowerBackup.portableLights => 'portable_lights',
        _ => name,
      };

  static PowerBackup fromWire(String v) => switch (v) {
        'battery_clippers' => PowerBackup.batteryClippers,
        'portable_lights' => PowerBackup.portableLights,
        _ => PowerBackup.values
            .firstWhere((p) => p.name == v, orElse: () => PowerBackup.inverter),
      };
}

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.roles,
    required this.countryCode,
    required this.profileComplete,
    required this.needsPhone,
    required this.isNewUser,
    this.serviceArea,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String fullName;

  /// Null for a social/email account that has not linked a number yet.
  final String? phone;
  final List<String> roles;
  final String countryCode;
  final bool profileComplete;

  /// True when the account signed in with Google or email and still has to
  /// verify a mobile number before it can book.
  final bool needsPhone;
  final bool isNewUser;

  /// Null until the client has chosen where they want service. Carried on the
  /// session so sign-in can route straight to the right screen instead of
  /// sending a returning client through onboarding again.
  final ServiceArea? serviceArea;

  factory AuthSession.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    final area = j['serviceArea'] as Map<String, dynamic>?;
    return AuthSession(
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      userId: user['id'] as String,
      fullName: user['fullName'] as String? ?? '',
      phone: user['phone'] as String?,
      roles: (user['roles'] as List).cast<String>(),
      countryCode: user['countryCode'] as String,
      profileComplete: j['profileComplete'] as bool? ?? false,
      needsPhone: j['needsPhone'] as bool? ?? false,
      isNewUser: j['isNewUser'] as bool? ?? false,
      serviceArea: area == null ? null : ServiceArea.fromJson(area),
    );
  }

  bool get isProvider => roles.contains('provider');
}

class ProviderSummary {
  const ProviderSummary({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.distanceKm,
    required this.rating,
    required this.ratingCount,
    required this.completedJobs,
    required this.hasPowerBackup,
    required this.isOnline,
    required this.fromPrice,
    required this.categories,
    required this.etaMinutes,
    this.venueMode = VenueMode.mobile,
    this.businessMode = BusinessMode.solo,
    this.shopAddress,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final double distanceKm;
  final double rating;
  final int ratingCount;
  final int completedJobs;
  final bool hasPowerBackup;
  final bool isOnline;
  final Money fromPrice;
  final List<ServiceCategory> categories;
  final int? etaMinutes;
  final VenueMode venueMode;
  final BusinessMode businessMode;

  /// Null unless this provider receives clients somewhere.
  final String? shopAddress;

  /// A salon is a place you travel to; a solo provider comes to you. The
  /// distinction changes what the card should say, not just what it shows.
  bool get isShop =>
      venueMode == VenueMode.inShop || businessMode == BusinessMode.salon;

  factory ProviderSummary.fromJson(Map<String, dynamic> j) => ProviderSummary(
        id: j['providerId'] as String,
        displayName: j['displayName'] as String,
        avatarUrl: j['avatarUrl'] as String?,
        distanceKm: (j['distanceKm'] as num).toDouble(),
        rating: (j['rating'] as num).toDouble(),
        ratingCount: j['ratingCount'] as int? ?? 0,
        completedJobs: j['completedJobs'] as int? ?? 0,
        hasPowerBackup: j['hasPowerBackup'] as bool? ?? false,
        isOnline: j['isOnline'] as bool? ?? false,
        fromPrice: Money.fromJson(j['fromPrice'] as Map<String, dynamic>),
        categories: (j['categories'] as List? ?? [])
            .map((c) => ServiceCategory.fromWire(c as String))
            .toList(),
        etaMinutes: j['etaMinutes'] as int?,
        venueMode: VenueMode.fromWire(j['venueMode'] as String?),
        businessMode: BusinessMode.fromWire(j['businessMode'] as String?),
        shopAddress: j['shopAddress'] as String?,
      );
}

enum VenueMode {
  mobile('mobile'),
  inShop('in_shop'),
  both('both');

  const VenueMode(this.wire);
  final String wire;

  /// Defaults to mobile rather than throwing. An unrecognised venue is a
  /// deployment skew, and refusing to render the whole feed over one is worse
  /// than showing a provider slightly wrong.
  static VenueMode fromWire(String? wire) => VenueMode.values
      .firstWhere((v) => v.wire == wire, orElse: () => VenueMode.mobile);
}

enum BusinessMode {
  solo('solo'),
  salon('salon'),
  salonStaff('salon_staff');

  const BusinessMode(this.wire);
  final String wire;

  static BusinessMode fromWire(String? wire) => BusinessMode.values
      .firstWhere((b) => b.wire == wire, orElse: () => BusinessMode.solo);
}

/// One movement in a provider's earnings history.
///
/// Deliberately a Money rather than a bare int: this is the screen where a
/// provider checks what they were paid, and a number rendered in the wrong
/// currency or off by a factor of a hundred is the fastest way to lose their
/// trust in the whole product.
class EarningsTransaction {
  const EarningsTransaction({
    required this.bookingId,
    required this.reference,
    required this.completedAt,
    required this.serviceMinor,
    required this.travelMinor,
    required this.commissionMinor,
    required this.currency,
  });

  final String bookingId;
  final String reference;
  final DateTime completedAt;

  /// The parts, kept as minor units and only combined by [netEarnings], so
  /// nothing here can drift the way a pre-summed float would.
  final int serviceMinor;
  final int travelMinor;
  final int commissionMinor;
  final String currency;

  /// What actually reached the wallet. Service plus travel, less commission —
  /// the same arithmetic the ledger performed at capture, shown back so a
  /// provider can check it rather than trust it.
  Money get netEarnings => Money(
      minor: serviceMinor + travelMinor - commissionMinor, currency: currency);

  factory EarningsTransaction.fromJson(Map<String, dynamic> j) =>
      EarningsTransaction(
        bookingId: j['bookingId'] as String,
        reference: j['reference'] as String,
        completedAt: DateTime.parse(j['completedAt'] as String),
        serviceMinor: (j['serviceMinor'] as num?)?.toInt() ?? 0,
        travelMinor: (j['travelMinor'] as num?)?.toInt() ?? 0,
        commissionMinor: (j['commissionMinor'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'ZAR',
      );
}

/// One line of an autocomplete list. Carries no coordinates — Google's
/// autocomplete does not return them, and asking for them per keystroke would
/// be billed as a full place lookup each time.
class AddressSuggestion {
  const AddressSuggestion({
    required this.placeId,
    required this.primary,
    required this.secondary,
  });

  final String placeId;

  /// "12 Sandton Drive"
  final String primary;

  /// "Sandton, Johannesburg"
  final String secondary;

  factory AddressSuggestion.fromJson(Map<String, dynamic> j) =>
      AddressSuggestion(
        placeId: j['placeId'] as String,
        primary: j['primary'] as String,
        secondary: j['secondary'] as String? ?? '',
      );
}

class ResolvedAddress {
  const ResolvedAddress({
    required this.formatted,
    required this.lat,
    required this.lng,
  });

  final String formatted;
  final double lat;
  final double lng;

  factory ResolvedAddress.fromJson(Map<String, dynamic> j) => ResolvedAddress(
        formatted: j['formatted'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

/// A place somebody books to often enough to name.
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.formatted,
    required this.lat,
    required this.lng,
    required this.isDefault,
    this.unitNotes,
    this.accessNotes,
  });

  final String id;

  /// "Home", "Work", "Mom's".
  final String label;
  final String formatted;
  final double lat;
  final double lng;
  final bool isDefault;

  /// "Flat 3B" — geocoders drop it and a provider in a lobby needs it.
  final String? unitNotes;

  /// "Buzzer 4B, dog in the yard." Only shared once a job is accepted.
  final String? accessNotes;

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        id: j['id'] as String,
        label: j['label'] as String,
        formatted: j['formatted'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        isDefault: j['isDefault'] as bool? ?? false,
        unitNotes: j['unitNotes'] as String?,
        accessNotes: j['accessNotes'] as String?,
      );
}

/// A suburb, as a person would name it. Always inside an area we serve.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.serviceAreaId,
    required this.serviceAreaName,
    required this.lat,
    required this.lng,
    this.postalCode,
    this.countryCode,
  });

  final String id;
  final String name;
  final String serviceAreaId;
  final String serviceAreaName;
  final double lat;
  final double lng;
  final String? postalCode;
  final String? countryCode;

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: j['name'] as String,
        serviceAreaId: j['serviceAreaId'] as String,
        serviceAreaName: j['serviceAreaName'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        postalCode: j['postalCode'] as String?,
        countryCode: j['countryCode'] as String?,
      );
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.durationMinutes,
    required this.requiresPower,
  });

  final String id;
  final String name;
  final String? description;
  final ServiceCategory category;
  final Money price;
  final int durationMinutes;
  final bool requiresPower;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        category: ServiceCategory.fromWire(j['category'] as String),
        price: Money(
            minor: j['priceMinor'] as int, currency: j['currency'] as String),
        durationMinutes: j['durationMinutes'] as int,
        requiresPower: j['requiresPower'] as bool? ?? false,
      );
}

class PriceQuote {
  const PriceQuote({
    required this.currency,
    required this.subtotalMinor,
    required this.travelFeeMinor,
    required this.serviceFeeMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.travelDistanceKm,
    required this.breakdown,
  });

  final String currency;
  final int subtotalMinor;
  final int travelFeeMinor;
  final int serviceFeeMinor;
  final int discountMinor;
  final int totalMinor;
  final double travelDistanceKm;
  final List<QuoteLine> breakdown;

  Money get total => Money(minor: totalMinor, currency: currency);

  factory PriceQuote.fromJson(Map<String, dynamic> j) => PriceQuote(
        currency: j['currency'] as String,
        subtotalMinor: j['subtotalMinor'] as int,
        travelFeeMinor: j['travelFeeMinor'] as int,
        serviceFeeMinor: j['serviceFeeMinor'] as int,
        discountMinor: j['discountMinor'] as int? ?? 0,
        totalMinor: j['totalMinor'] as int,
        travelDistanceKm: (j['travelDistanceKm'] as num?)?.toDouble() ?? 0,
        breakdown: (j['breakdown'] as List? ?? [])
            .map((b) => QuoteLine.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class QuoteLine {
  const QuoteLine(
      {required this.label, required this.amountMinor, required this.kind});
  final String label;
  final int amountMinor;
  final String kind;

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        label: j['label'] as String,
        amountMinor: j['amountMinor'] as int,
        kind: j['kind'] as String? ?? 'charge',
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.reference,
    required this.status,
    required this.destinationAddress,
    required this.total,
    required this.providerId,
    required this.providerName,
    required this.serviceIds,
    this.arrivedAt,
    this.completedAt,
    this.cancelledAt,
    required this.scheduledStart,
    required this.createdAt,
    this.assignedStaffId,
    this.assignedStaffName,
    this.reviewedByMe = false,
    this.breakdown = const [],
  });

  final String id;
  final String reference;
  final BookingStatus status;
  final String destinationAddress;
  final Money total;

  /// The lines behind [total] as the server itemised them: services, add-ons,
  /// travel, platform fee. Rendered verbatim; the app never sums them. Empty
  /// when the endpoint sends only the total.
  final List<QuoteLine> breakdown;
  final String? providerId;
  final String? providerName;
  final List<String> serviceIds;
  final DateTime? arrivedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? scheduledStart;
  final DateTime createdAt;

  /// Salon bookings only: the staff member the owner handed this job to.
  final String? assignedStaffId;
  final String? assignedStaffName;

  /// Whether the caller has already left a review on this booking.
  final bool reviewedByMe;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as String,
        reference: j['reference'] as String,
        status: BookingStatus.fromWire(j['status'] as String),
        destinationAddress: j['destinationAddress'] as String? ?? '',
        total: Money.fromJson(j['total'] as Map<String, dynamic>),
        providerId: j['providerId'] as String?,
        providerName: j['providerName'] as String?,
        serviceIds: (j['serviceIds'] as List? ?? []).cast<String>(),
        arrivedAt: j['arrivedAt'] != null
            ? DateTime.parse(j['arrivedAt'] as String)
            : null,
        completedAt: j['completedAt'] != null
            ? DateTime.parse(j['completedAt'] as String)
            : null,
        cancelledAt: j['cancelledAt'] != null
            ? DateTime.parse(j['cancelledAt'] as String)
            : null,
        scheduledStart: j['scheduledStart'] != null
            ? DateTime.parse(j['scheduledStart'] as String)
            : null,
        createdAt: DateTime.parse(j['createdAt'] as String),
        assignedStaffId: j['assignedStaffId'] as String?,
        assignedStaffName: j['assignedStaffName'] as String?,
        reviewedByMe: j['reviewedByMe'] as bool? ?? false,
        breakdown: (j['breakdown'] as List? ?? [])
            .map((b) => QuoteLine.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class TrackingUpdate {
  const TrackingUpdate({
    required this.bookingId,
    required this.status,
    required this.providerLocation,
    required this.etaMinutes,
    required this.distanceRemainingKm,
  });

  final String bookingId;
  final BookingStatus status;
  final GeoPoint? providerLocation;
  final int? etaMinutes;
  final double? distanceRemainingKm;

  factory TrackingUpdate.fromJson(Map<String, dynamic> j) => TrackingUpdate(
        bookingId: j['bookingId'] as String,
        status: BookingStatus.fromWire(j['status'] as String),
        providerLocation: j['providerLocation'] != null
            ? GeoPoint.fromJson(j['providerLocation'] as Map<String, dynamic>)
            : null,
        etaMinutes: j['etaMinutes'] as int?,
        distanceRemainingKm: (j['distanceRemainingKm'] as num?)?.toDouble(),
      );
}

class DispatchOffer {
  const DispatchOffer({
    required this.offerId,
    required this.bookingId,
    required this.reference,
    required this.serviceNames,
    required this.distanceKm,
    required this.etaMinutes,
    required this.payout,
    required this.destinationAddress,
    required this.expiresAt,
    required this.clientRating,
    this.scheduledStart,
    this.durationMinutes = 0,
  });

  final String offerId;
  final String bookingId;
  final String reference;
  final List<String> serviceNames;
  final double distanceKm;
  final int etaMinutes;
  final Money payout;
  final String destinationAddress;
  final DateTime expiresAt;
  final double clientRating;

  /// Null for an instant job. The dispatch service sends this for scheduled
  /// bookings and the offer overlay shows it, so a provider knows whether they
  /// are being asked to leave now or to hold a slot on Thursday.
  final DateTime? scheduledStart;

  /// How long the work itself takes. Distance answers how far, this answers how
  /// long you are committing for — the two together are what makes a payout
  /// worth accepting or not.
  final int durationMinutes;

  Duration get remaining => expiresAt.difference(DateTime.now());

  factory DispatchOffer.fromJson(Map<String, dynamic> j) => DispatchOffer(
        offerId: j['offerId'] as String,
        bookingId: j['bookingId'] as String,
        reference: j['reference'] as String,
        serviceNames: (j['serviceNames'] as List? ?? []).cast<String>(),
        durationMinutes: j['durationMinutes'] as int? ?? 0,
        distanceKm: (j['distanceKm'] as num).toDouble(),
        etaMinutes: j['etaMinutes'] as int? ?? 0,
        payout: Money.fromJson(j['payout'] as Map<String, dynamic>),
        destinationAddress: j['destinationAddress'] as String? ?? '',
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        clientRating: (j['clientRating'] as num?)?.toDouble() ?? 5,
        scheduledStart: j['scheduledStart'] != null
            ? DateTime.parse(j['scheduledStart'] as String)
            : null,
      );
}

class GridStatus {
  const GridStatus({
    required this.countryCode,
    required this.stage,
    required this.source,
    required this.nextWindowStart,
    required this.nextWindowEnd,
  });

  final String countryCode;
  final int stage;
  final String source;
  final DateTime? nextWindowStart;
  final DateTime? nextWindowEnd;

  bool get isActive => stage > 0;

  /// At stage 4 and above the app forces the power-backup filter on. A pro
  /// with mains-only clippers is a wasted trip, and a wasted trip in this
  /// business costs the customer their appointment slot, not just time.
  bool get forcesPowerFilter => stage >= 4;

  String get label => stage == 0 ? 'Grid stable' : 'Stage $stage active';

  factory GridStatus.fromJson(Map<String, dynamic> j) => GridStatus(
        countryCode: j['countryCode'] as String,
        stage: j['stage'] as int? ?? 0,
        source: j['source'] as String? ?? 'unknown',
        nextWindowStart: j['nextWindow']?['start'] != null
            ? DateTime.parse(j['nextWindow']['start'] as String)
            : null,
        nextWindowEnd: j['nextWindow']?['end'] != null
            ? DateTime.parse(j['nextWindow']['end'] as String)
            : null,
      );
}

/// The signed-in user as the server currently sees them.
///
/// Distinct from [AuthSession], which is what a sign-in returned at a point in
/// time. Roles and verification state can change while a token is still valid,
/// so anything that gates behaviour reads this rather than the stored session.
/// A metro Freshly operates in, with the centroid discovery falls back to
/// when there is no usable GPS fix.
class ServiceArea {
  const ServiceArea({
    required this.id,
    required this.slug,
    required this.name,
    required this.lat,
    required this.lng,
    this.countryCode,
    this.placeId,
    this.placeName,
  });

  final String id;
  final String slug;
  final String name;
  final double lat;
  final double lng;
  final String? countryCode;

  /// The suburb the user actually chose, when they chose one.
  final String? placeId;
  final String? placeName;

  /// What to show them. "Rosebank" is an answer they recognise;
  /// "Johannesburg North" is one they would have to work out.
  String get displayName => placeName ?? name;

  factory ServiceArea.fromJson(Map<String, dynamic> j) => ServiceArea(
        id: j['id'] as String,
        slug: j['slug'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        countryCode: j['countryCode'] as String?,
        placeId: j['placeId'] as String?,
        placeName: j['placeName'] as String?,
      );
}

class CategorySummary {
  const CategorySummary({
    required this.category,
    required this.providerCount,
  });

  final ServiceCategory category;
  final int providerCount;

  factory CategorySummary.fromJson(Map<String, dynamic> j) => CategorySummary(
        category: ServiceCategory.fromWire(j['category'] as String),
        providerCount: j['providerCount'] as int? ?? 0,
      );
}

class CatalogService {
  const CatalogService({
    required this.id,
    required this.name,
    required this.category,
    required this.typicalDurationMinutes,
    required this.requiresPower,
    required this.requiresLicence,
    this.description,
  });

  final String id;
  final String name;
  final ServiceCategory category;
  final int typicalDurationMinutes;
  final bool requiresPower;
  final bool requiresLicence;
  final String? description;

  factory CatalogService.fromJson(Map<String, dynamic> j) => CatalogService(
        id: j['id'] as String,
        name: j['name'] as String,
        category: ServiceCategory.fromWire(j['category'] as String),
        typicalDurationMinutes: j['typicalDurationMinutes'] as int? ?? 0,
        requiresPower: j['requiresPower'] as bool? ?? false,
        requiresLicence: j['requiresLicence'] as bool? ?? false,
        description: j['description'] as String?,
      );
}

class ProviderMenuItem {
  const ProviderMenuItem({
    required this.id,
    required this.catalogServiceId,
    required this.name,
    required this.category,
    required this.price,
    required this.durationMinutes,
    required this.requiresPower,
    required this.requiresLicence,
    this.description,
  });

  final String id;

  /// The catalogue template this was built from. Null for a legacy service
  /// that predates the canonical catalogue, which can be removed but not
  /// repriced from the app.
  final String? catalogServiceId;
  final String name;
  final ServiceCategory category;
  final Money price;
  final int durationMinutes;
  final bool requiresPower;
  final bool requiresLicence;
  final String? description;

  factory ProviderMenuItem.fromJson(Map<String, dynamic> j) {
    // The menu endpoint nests the price as `{minor, currency}`; the add
    // endpoint and older fixtures carry `priceMinor` and `currency` flat.
    final nested = j['price'] as Map<String, dynamic>?;
    final price = nested != null
        ? Money.fromJson(nested)
        : Money(
            minor: (j['priceMinor'] as num?)?.toInt() ?? 0,
            currency: j['currency'] as String? ?? 'USD');
    return ProviderMenuItem(
      id: j['id'] as String,
      catalogServiceId: (j['catalogServiceId'] ?? j['templateId']) as String?,
      name: j['name'] as String,
      category: ServiceCategory.fromWire(j['category'] as String),
      price: price,
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      requiresPower: j['requiresPower'] as bool? ?? false,
      requiresLicence:
          (j['requiresLicence'] ?? j['requiresCredential']) as bool? ?? false,
      description: j['description'] as String?,
    );
  }
}

class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.url,
    this.tags = const [],
  });

  final String id;
  final String url;
  final List<String> tags;

  factory PortfolioItem.fromJson(Map<String, dynamic> j) => PortfolioItem(
        id: j['id'] as String,
        url: j['url'] as String,
        tags: (j['tags'] as List? ?? []).cast<String>(),
      );
}

class ClientSummary {
  const ClientSummary({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    required this.phone,
    required this.lastBookingAt,
    required this.bookingCount,
  });

  final String id;
  final String fullName;
  final String? avatarUrl;
  final String phone;
  final DateTime lastBookingAt;
  final int bookingCount;

  factory ClientSummary.fromJson(Map<String, dynamic> j) => ClientSummary(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        avatarUrl: j['avatarUrl'] as String?,
        phone: j['phone'] as String,
        lastBookingAt: DateTime.parse(j['lastBookingAt'] as String),
        bookingCount: j['bookingCount'] as int,
      );
}

class ClientDetail {
  const ClientDetail({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    required this.phone,
    required this.rating,
    required this.ratingCount,
    required this.joinedAt,
    required this.notes,
    required this.history,
  });

  final String id;
  final String fullName;
  final String? avatarUrl;
  final String phone;
  final double rating;
  final int ratingCount;
  final DateTime joinedAt;
  final String notes;
  final List<ClientHistoryItem> history;

  factory ClientDetail.fromJson(Map<String, dynamic> j) => ClientDetail(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        avatarUrl: j['avatarUrl'] as String?,
        phone: j['phone'] as String,
        rating: (j['rating'] as num).toDouble(),
        ratingCount: j['ratingCount'] as int,
        joinedAt: DateTime.parse(j['joinedAt'] as String),
        notes: j['notes'] as String? ?? '',
        history: (j['history'] as List)
            .map((e) => ClientHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ClientHistoryItem {
  const ClientHistoryItem({
    required this.id,
    required this.reference,
    required this.status,
    required this.createdAt,
    required this.total,
    required this.services,
  });

  final String id;
  final String reference;
  final BookingStatus status;
  final DateTime createdAt;
  final Money total;
  final List<String> services;

  factory ClientHistoryItem.fromJson(Map<String, dynamic> j) =>
      ClientHistoryItem(
        id: j['id'] as String,
        reference: j['reference'] as String,
        status: BookingStatus.fromWire(j['status'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        total: Money.fromJson(j['total'] as Map<String, dynamic>),
        services: (j['services'] as List).cast<String>(),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.bookingId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String bookingId;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        bookingId: j['bookingId'] as String,
        authorId: j['authorId'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        isRead: j['isRead'] as bool? ?? false,
      );
}

/// A market Freshly is open in. Only live markets are returned, so a country
/// missing from this list is one we cannot serve yet.
class Market {
  const Market({
    required this.code,
    required this.name,
    required this.currency,
    required this.dialPrefix,
    required this.phoneLength,
    required this.cancellationWindowMinutes,
    required this.cancellationFeeBps,
    required this.noShowGraceMinutes,
    this.emergencyNumber = '112',
  });

  final String code;
  final String name;
  final String currency;
  final String dialPrefix;
  final int phoneLength;
  final int cancellationWindowMinutes;
  final int cancellationFeeBps;
  final int noShowGraceMinutes;

  /// Who to call when SOS cannot be sent: the police line for the market.
  final String emergencyNumber;

  factory Market.fromJson(Map<String, dynamic> j) => Market(
        code: j['code'] as String,
        name: j['name'] as String,
        currency: j['currency'] as String? ?? 'ZAR',
        dialPrefix: j['dialPrefix'] as String? ?? '+27',
        phoneLength: (j['phoneLength'] as num?)?.toInt() ?? 9,
        cancellationWindowMinutes: j['cancellationWindowMinutes'] as int? ?? 0,
        cancellationFeeBps: j['cancellationFeeBps'] as int? ?? 0,
        noShowGraceMinutes: j['noShowGraceMinutes'] as int? ?? 10,
        emergencyNumber: j['emergencyNumber'] as String? ?? '112',
      );
}

class UploadInstruction {
  const UploadInstruction({
    required this.url,
    required this.key,
    required this.maxSize,
    required this.contentTypes,
  });

  final String url;
  final String key;
  final int maxSize;
  final List<String> contentTypes;

  factory UploadInstruction.fromJson(Map<String, dynamic> j) =>
      UploadInstruction(
        url: j['url'] as String,
        key: j['key'] as String,
        maxSize: j['maxSize'] as int,
        contentTypes: (j['contentTypes'] as List).cast<String>(),
      );
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.roles,
    required this.countryCode,
    required this.profileComplete,
    this.needsPhone = false,
    this.avatarUrl,
    this.providerId,
    this.kycStatus,
    this.isOnline = false,
    this.serviceArea,
  });

  final String id;
  final String fullName;

  /// Null for a social/email account that has not linked a number yet.
  final String? phone;
  final List<String> roles;
  final String countryCode;
  final bool profileComplete;

  /// True when this account still has to verify a mobile number before booking.
  final bool needsPhone;
  final String? avatarUrl;
  final String? providerId;
  final String? kycStatus;
  final bool isOnline;

  /// Null until the client has been asked. The router uses that to decide
  /// whether onboarding is finished.
  final ServiceArea? serviceArea;

  bool get isProvider => roles.contains('provider');
  bool get isVerifiedProvider => isProvider && kycStatus == 'verified';

  factory CurrentUser.fromJson(Map<String, dynamic> j) {
    final provider = j['provider'] as Map<String, dynamic>?;
    final area = j['serviceArea'] as Map<String, dynamic>?;
    return CurrentUser(
      id: j['id'] as String,
      fullName: j['fullName'] as String? ?? '',
      phone: j['phone'] as String?,
      roles: (j['roles'] as List? ?? const []).cast<String>(),
      countryCode: j['countryCode'] as String? ?? 'ZA',
      profileComplete: j['profileComplete'] as bool? ?? false,
      needsPhone: j['needsPhone'] as bool? ?? false,
      avatarUrl: j['avatarUrl'] as String?,
      providerId: provider?['id'] as String?,
      kycStatus: provider?['kycStatus'] as String?,
      isOnline: provider?['isOnline'] as bool? ?? false,
      serviceArea: area == null ? null : ServiceArea.fromJson(area),
    );
  }
}

/// What a new provider tells us about their business at sign-up.
class ProviderSignUp {
  const ProviderSignUp({
    required this.displayName,
    required this.businessMode,
    required this.categories,
    required this.venueMode,
    required this.lat,
    required this.lng,
    this.shopAddress,
    this.travelRadiusKm,
    this.powerBackup = const [],
    this.bio,
  });

  final String displayName;
  final String businessMode; // solo | salon
  final List<ServiceCategory> categories;
  final String venueMode; // mobile | in_shop | both
  final double lat;
  final double lng;
  final String? shopAddress;
  final double? travelRadiusKm;
  final List<PowerBackup> powerBackup;
  final String? bio;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'businessMode': businessMode,
        'categories': categories.map((c) => c.wire).toList(),
        'venueMode': venueMode,
        'lat': lat,
        'lng': lng,
        if (shopAddress != null) 'shopAddress': shopAddress,
        if (travelRadiusKm != null) 'travelRadiusKm': travelRadiusKm,
        if (powerBackup.isNotEmpty)
          'powerBackup': powerBackup.map((p) => p.wire).toList(),
        if (bio != null && bio!.isNotEmpty) 'bio': bio,
      };
}

/// The provider's own business as the server holds it.
class ProviderBusiness {
  const ProviderBusiness({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.businessMode,
    required this.categories,
    required this.venueMode,
    required this.powerBackup,
    required this.shopAddress,
    required this.travelRadiusKm,
    required this.acceptsInstant,
    required this.acceptsScheduled,
    required this.kycStatus,
    required this.isOnline,
    required this.rating,
    required this.ratingCount,
    required this.completedJobs,
    required this.currency,
    required this.baseLocation,
    required this.serviceAreaName,
  });

  final String id;
  final String displayName;
  final String? bio;
  final String businessMode;
  final List<ServiceCategory> categories;
  final String venueMode;
  final List<PowerBackup> powerBackup;
  final String? shopAddress;
  final double travelRadiusKm;
  final bool acceptsInstant;
  final bool acceptsScheduled;
  final String kycStatus;
  final bool isOnline;
  final double rating;
  final int ratingCount;
  final int completedJobs;
  final String currency;
  final GeoPoint? baseLocation;
  final String? serviceAreaName;

  factory ProviderBusiness.fromJson(Map<String, dynamic> j) {
    final base = j['baseLocation'] as Map<String, dynamic>?;
    final area = j['serviceArea'] as Map<String, dynamic>?;
    return ProviderBusiness(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      bio: j['bio'] as String?,
      businessMode: j['businessMode'] as String? ?? 'solo',
      categories: (j['categories'] as List? ?? [])
          .map((c) => ServiceCategory.fromWire(c as String))
          .toList(),
      venueMode: j['venueMode'] as String? ?? 'mobile',
      powerBackup: (j['powerBackup'] as List? ?? [])
          .map((p) => PowerBackup.fromWire(p as String))
          .toList(),
      shopAddress: j['shopAddress'] as String?,
      travelRadiusKm: (j['travelRadiusKm'] as num?)?.toDouble() ?? 10,
      acceptsInstant: j['acceptsInstant'] as bool? ?? true,
      acceptsScheduled: j['acceptsScheduled'] as bool? ?? true,
      kycStatus: j['kycStatus'] as String? ?? 'pending',
      isOnline: j['isOnline'] as bool? ?? false,
      rating: (j['rating'] as num?)?.toDouble() ?? 5,
      ratingCount: j['ratingCount'] as int? ?? 0,
      completedJobs: j['completedJobs'] as int? ?? 0,
      currency: j['currency'] as String? ?? 'USD',
      baseLocation: base == null
          ? null
          : GeoPoint(
              (base['lat'] as num).toDouble(), (base['lng'] as num).toDouble()),
      serviceAreaName: area?['name'] as String?,
    );
  }
}

/// One working window on one weekday. Weekday 0 is Sunday, as in the database.
class WorkingHours {
  const WorkingHours({
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
  });

  final int weekday;

  /// "HH:mm", 24-hour.
  final String startsAt;
  final String endsAt;

  factory WorkingHours.fromJson(Map<String, dynamic> j) => WorkingHours(
        weekday: j['weekday'] as int,
        startsAt: j['startsAt'] as String,
        endsAt: j['endsAt'] as String,
      );

  Map<String, dynamic> toJson() =>
      {'weekday': weekday, 'startsAt': startsAt, 'endsAt': endsAt};
}

/// An extra the provider has suggested mid-job, waiting on the client.
class AddonRequest {
  const AddonRequest({
    required this.itemId,
    required this.name,
    required this.price,
  });

  final String itemId;
  final String name;
  final Money price;

  factory AddonRequest.fromJson(Map<String, dynamic> j) => AddonRequest(
        itemId: j['itemId'] as String,
        name: j['name'] as String,
        price: Money(
            minor: j['priceMinor'] as int, currency: j['currency'] as String),
      );
}

/// A help request or complaint, with the thread of replies on it.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.messages,
  });

  final String id;
  final String subject;
  final String body;

  /// 'open' or 'closed'.
  final String status;
  final DateTime createdAt;
  final List<SupportMessage> messages;

  bool get isOpen => status == 'open';

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: j['id'] as String,
        subject: j['subject'] as String,
        body: j['body'] as String,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        messages: (j['messages'] as List? ?? [])
            .map((m) => SupportMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.isStaff,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final bool isStaff;
  final String body;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: j['id'] as String,
        isStaff: j['isStaff'] as bool? ?? false,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// One of the two invoices a completed booking produces: the provider's to
/// the client, and Freshly's to the provider for its fees.
class Invoice {
  const Invoice({
    required this.id,
    required this.kind,
    required this.number,
    required this.issuedAt,
    required this.total,
  });

  final String id;

  /// 'provider_to_client' or 'platform_to_provider'.
  final String kind;
  final String number;
  final DateTime issuedAt;
  final Money total;

  bool get isPlatformFee => kind == 'platform_to_provider';

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'] as String,
        kind: j['kind'] as String,
        number: j['number'] as String,
        issuedAt: DateTime.parse(j['issuedAt'] as String),
        total: Money(
            minor: j['totalMinor'] as int, currency: j['currency'] as String),
      );
}

/// A salon's staff member, or an invitation that has not been taken up yet.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.phoneMasked,
    required this.status,
    required this.jobsThisWeek,
    required this.completedJobs,
  });

  final String id;

  /// 'staff' (a provider row) or 'invite' (a pending invitation).
  final String kind;
  final String? displayName;
  final String phoneMasked;

  /// 'active' or 'pending'.
  final String status;
  final int jobsThisWeek;
  final int completedJobs;

  bool get isPending => status == 'pending';

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'staff',
        displayName: j['displayName'] as String?,
        phoneMasked: j['phone'] as String? ?? '',
        status: j['status'] as String? ?? 'active',
        jobsThisWeek: j['jobsThisWeek'] as int? ?? 0,
        completedJobs: j['completedJobs'] as int? ?? 0,
      );
}

/// An invitation to join a salon's team, waiting on the person invited.
class StaffInvite {
  const StaffInvite(
      {required this.id, required this.salonName, required this.salonSuburb});

  final String id;
  final String salonName;
  final String? salonSuburb;

  factory StaffInvite.fromJson(Map<String, dynamic> j) => StaffInvite(
        id: j['id'] as String,
        salonName: j['salonName'] as String,
        salonSuburb: j['salonSuburb'] as String?,
      );
}
