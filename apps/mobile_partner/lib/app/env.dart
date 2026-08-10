/// Build-time configuration for the partner app.
class Env {
  const Env._();

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000');
  static const String realtimeUrl = String.fromEnvironment('REALTIME_URL',
      defaultValue: 'http://10.0.2.2:3000');
  static const String mapsApiKey = String.fromEnvironment('MAPS_API_KEY');
  static const String flavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static bool get isProduction => flavor == 'production';
}
