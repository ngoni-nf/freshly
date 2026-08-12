import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Freshly design system.
///
/// The palette is built around a mint-forward green — "fresh" read literally —
/// with a deep charcoal for surfaces so portfolio photography stays the loudest
/// thing on screen. Typography scales are generous because a large share of
/// users in both markets are on small, low-density handsets held at arm's
/// length in bad light.
class FreshlyColors {
  const FreshlyColors._();

  static const Color mint = Color(0xFF00C48C);
  static const Color mintDark = Color(0xFF00A375);
  static const Color mintSoft = Color(0xFFE6FAF3);

  static const Color ink = Color(0xFF10161F);
  static const Color inkMuted = Color(0xFF5B6675);
  static const Color line = Color(0xFFE3E8EF);
  static const Color canvas = Color(0xFFF7F9FC);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color gold = Color(0xFFFFB020); // ratings, power-backup badge
  static const Color crimson = Color(0xFFE5484D); // SOS, destructive
  static const Color info = Color(0xFF2E7CF6);
  static const Color loadShedding = Color(0xFFFF8A3D);
}

class FreshlySpacing {
  const FreshlySpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double radius = 16;
  static const double radiusLarge = 24;

  /// Minimum tappable edge. Below this, thumb accuracy collapses on the
  /// 5-inch devices that dominate both markets.
  static const double minTapTarget = 48;
}

/// Apple's type system, as far as it can lawfully be taken.
///
/// SF Pro is licensed for designing and building software for Apple's own
/// platforms. It may not be bundled into an Android binary, so this resolves
/// per platform rather than shipping one file everywhere:
///
///   - iOS and macOS: the family name below is Apple's own system font, so the
///     apps render in genuine SF Pro.
///   - Android and elsewhere: `null` hands Flutter the platform default. Drop
///     Inter into `assets/fonts/` and name it here to match SF more closely —
///     it was drawn as an SF-alike and is under the Open Font License.
///
/// The metrics matter more than the file. What reads as "Apple" is mostly the
/// tracking: SF tightens sharply as size increases and loosens below body
/// size, which is what `_appleTracking` reproduces. Applied over whichever
/// family is actually available, it gets most of the way there on any device.
class FreshlyType {
  const FreshlyType._();

  static String? get family {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // Apple's system font, resolved by the OS. Not a bundled file.
        return '.SF Pro Text';
      default:
        return null;
    }
  }

  static String? get displayFamily {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        // Apple switches to the Display cut above 20pt; the two differ in
        // tracking and aperture, and using Text at headline sizes is the most
        // common way an imitation gives itself away.
        return '.SF Pro Display';
      default:
        return null;
    }
  }

  /// SF's optical tracking, in logical pixels, approximated from Apple's
  /// published table. Negative above body size, positive below it.
  static double tracking(double fontSize) {
    if (fontSize >= 34) return -1.0;
    if (fontSize >= 28) return -0.7;
    if (fontSize >= 22) return -0.5;
    if (fontSize >= 20) return -0.4;
    if (fontSize >= 17) return -0.4;
    if (fontSize >= 15) return -0.2;
    if (fontSize >= 13) return 0.0;
    return 0.1;
  }

  static TextStyle style(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: size >= 20 ? displayFamily : family,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking(size),
        height: height,
        color: color,
      );

  /// Apple's own steps, so sizes are theirs rather than invented near them.
  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
        displayLarge: style(34, weight: FontWeight.w700, height: 1.2, color: ink),
        displayMedium: style(28, weight: FontWeight.w700, height: 1.2, color: ink),
        displaySmall: style(26, weight: FontWeight.w700, height: 1.2, color: ink),
        headlineLarge: style(28, weight: FontWeight.w700, height: 1.2, color: ink),
        headlineMedium: style(24, weight: FontWeight.w700, height: 1.25, color: ink),
        headlineSmall: style(22, weight: FontWeight.w600, height: 1.27, color: ink),
        titleLarge: style(20, weight: FontWeight.w600, height: 1.25, color: ink),
        titleMedium: style(17, weight: FontWeight.w600, height: 1.29, color: ink),
        titleSmall: style(15, weight: FontWeight.w600, height: 1.33, color: ink),
        bodyLarge: style(17, height: 1.29, color: ink),
        bodyMedium: style(15, height: 1.33, color: ink),
        bodySmall: style(13, height: 1.38, color: muted),
        labelLarge: style(17, weight: FontWeight.w600, color: ink),
        labelMedium: style(13, weight: FontWeight.w500, color: muted),
        labelSmall: style(11, weight: FontWeight.w500, color: muted),
      );
}

class FreshlyTheme {
  const FreshlyTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: FreshlyColors.mint,
      brightness: brightness,
      primary: FreshlyColors.mint,
      surface: isDark ? const Color(0xFF161C26) : FreshlyColors.surface,
      error: FreshlyColors.crimson,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final ink = isDark ? Colors.white : FreshlyColors.ink;
    final muted = isDark ? const Color(0xFF9AA6B6) : FreshlyColors.inkMuted;

    return base.copyWith(
      textTheme: FreshlyType.textTheme(ink, muted),
      primaryTextTheme: FreshlyType.textTheme(ink, muted),
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0C1017) : FreshlyColors.canvas,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor:
            isDark ? const Color(0xFF0C1017) : FreshlyColors.canvas,
        foregroundColor: isDark ? Colors.white : FreshlyColors.ink,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: FreshlyType.style(
          20,
          weight: FontWeight.w700,
          color: isDark ? Colors.white : FreshlyColors.ink,
        ),
      ),
      // CardThemeData, not CardTheme: ThemeData's *Theme slots moved to their
      // matching *ThemeData types in Flutter 3.32.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: isDark ? const Color(0xFF232B38) : FreshlyColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(FreshlySpacing.minTapTarget + 4),
          backgroundColor: FreshlyColors.mint,
          foregroundColor: Colors.white,
          textStyle: FreshlyType.style(17, weight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(FreshlySpacing.minTapTarget),
          foregroundColor: isDark ? Colors.white : FreshlyColors.ink,
          side: BorderSide(
              color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161C26) : FreshlyColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: const BorderSide(color: FreshlyColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: BorderSide(
              color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: const BorderSide(color: FreshlyColors.mint, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(
            color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
        selectedColor: FreshlyColors.mintSoft,
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF232B38) : FreshlyColors.line,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(FreshlySpacing.radiusLarge)),
        ),
      ),
    );
  }
}
