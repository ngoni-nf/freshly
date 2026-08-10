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

  static const String flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProduction => flavor == 'production';
}
