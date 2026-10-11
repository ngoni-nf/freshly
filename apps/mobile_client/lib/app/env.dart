/// Build-time configuration.
///
/// Supplied with --dart-define so a single codebase produces the staging and
/// production iOS and Android binaries without a code change:
///   flutter build ipa --dart-define=API_BASE_URL=https://api.freshly.africa
class Env {
  const Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String realtimeUrl = String.fromEnvironment(
    'REALTIME_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  static const String flavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProduction => flavor == 'production';

  /// Debug-only location override, as "lat,lng".
  ///
  ///     flutter run --dart-define=DEV_LOCATION=-17.7932,31.0361   # Avondale, Harare
  ///     flutter run --dart-define=DEV_LOCATION=-26.1076,28.0473   # Sandton
  ///
  /// The Android emulator reports Mountain View, and `adb emu geo fix` is
  /// unreliable on recent system images — it answers OK and changes nothing.
  /// Every service area is geofenced, so without this the app correctly
  /// reports "not live in this area yet" and cannot be exercised at all.
  /// Read only in debug builds, so it can never affect a release.
  static const String devLocation = String.fromEnvironment('DEV_LOCATION');

  static ({double lat, double lng})? get devLatLng {
    if (devLocation.isEmpty) return null;
    final parts = devLocation.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }
}
