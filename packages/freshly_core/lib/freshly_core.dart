/// Shared foundation for the Freshly client and partner apps.
///
/// Both apps ship from one Flutter codebase each and compile to native iOS and
/// Android binaries. Everything that must behave identically on both sides of
/// the marketplace — money maths, wire models, auth and token refresh, the
/// realtime channel, and the design system — lives here so the two apps cannot
/// drift apart.
library freshly_core;

export 'src/models/models.dart';
export 'src/network/api_client.dart';
export 'src/realtime/realtime_client.dart';
export 'src/theme/freshly_theme.dart';
export 'src/widgets/gallery_viewer.dart';
export 'src/widgets/chat_screen.dart';
export 'src/util/money.dart';
export 'src/util/formatters.dart';
