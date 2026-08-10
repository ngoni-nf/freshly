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

  static const Color gold = Color(0xFFFFB020);      // ratings, power-backup badge
  static const Color crimson = Color(0xFFE5484D);   // SOS, destructive
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

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? const Color(0xFF0C1017) : FreshlyColors.canvas,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: isDark ? const Color(0xFF0C1017) : FreshlyColors.canvas,
        foregroundColor: isDark ? Colors.white : FreshlyColors.ink,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : FreshlyColors.ink,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(color: isDark ? const Color(0xFF232B38) : FreshlyColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(FreshlySpacing.minTapTarget + 4),
          backgroundColor: FreshlyColors.mint,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(FreshlySpacing.minTapTarget),
          foregroundColor: isDark ? Colors.white : FreshlyColors.ink,
          side: BorderSide(color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161C26) : FreshlyColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: const BorderSide(color: FreshlyColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: BorderSide(color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          borderSide: const BorderSide(color: FreshlyColors.mint, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: isDark ? const Color(0xFF2C3542) : FreshlyColors.line),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(FreshlySpacing.radiusLarge)),
        ),
      ),
    );
  }
}
