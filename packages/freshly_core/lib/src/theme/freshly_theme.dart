import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Freshly design system — "Refined Freshly".
///
/// Obsidian carries weight, mint carries energy, and photography carries
/// everything else. Mint is never a text colour on a light surface: at 1.4:1
/// it is invisible in the midday sun most of these phones are used in. On a
/// mint fill the text is obsidian (13:1); as a text colour on white the brand
/// green is Deep Jade (4.6:1).
class FreshlyColors {
  const FreshlyColors._();

  /// Electric Mint. Fills, focus rings, the "online" dot, and anything sitting
  /// on obsidian. Never text on white.
  static const Color mint = Color(0xFF00F59B);

  /// Deep Jade: the brand green wherever it has to be read on a light
  /// surface — prices, links, selected labels, icons. 4.6:1 on white.
  static const Color mintDark = Color(0xFF00875A);

  /// Tinted wash behind brand icons and selected states.
  static const Color mintSoft = Color(0xFFE3FBF1);

  /// Text on [mintSoft]. 8:1.
  static const Color mintInk = Color(0xFF00563A);

  /// Obsidian Jet. Hero headers, the primary dark button, the selected
  /// navigation pill, and every label sitting on a mint fill.
  static const Color obsidian = Color(0xFF0B0F19);

  /// One step up from obsidian, for cards and controls that sit on it.
  static const Color obsidianRaised = Color(0xFF161C28);

  static const Color ink = Color(0xFF0F172A);

  /// Cool Slate: placeholder text, inactive icons, text on obsidian.
  static const Color inkMuted = Color(0xFF94A3B8);

  /// Body copy that is secondary but still has to be read. 5.5:1.
  static const Color inkSubtle = Color(0xFF5B6675);

  static const Color line = Color(0xFFE6EBF1);
  static const Color canvas = Color(0xFFF6F8FB);

  /// Input and chip fill on [canvas]: separates a control from the page
  /// without a border competing with the card edges around it.
  static const Color field = Color(0xFFEEF2F7);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color gold = Color(0xFFFFB020); // stars and backup-power marks
  static const Color goldInk = Color(0xFFB45309); // the same, as readable text
  static const Color crimson = Color(0xFFE5484D); // SOS, destructive
  static const Color crimsonSoft = Color(0xFFFDECEC);
  static const Color info = Color(0xFF2E7CF6);
  static const Color loadShedding = Color(0xFFFF8A3D);

  /// Load-shedding orange as text: the fill colour fails on its own wash.
  static const Color loadSheddingInk = Color(0xFFC2410C);
  static const Color loadSheddingSoft = Color(0xFFFFF3EB);
}

class FreshlySpacing {
  const FreshlySpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double radius = 18;
  static const double radiusLarge = 28;
  static const double radiusSmall = 12;

  /// Minimum tappable edge. Below this, thumb accuracy collapses on the
  /// 5-inch devices that dominate both markets.
  static const double minTapTarget = 48;

  static const double buttonHeight = 54;
  static const double buttonRadius = 16;
}

/// Soft, low elevation for things that float: photo cards, sticky bars,
/// sheets. Borders do the work everywhere else.
class FreshlyShadows {
  const FreshlyShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F0B0F19),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x0F0B0F19),
      blurRadius: 24,
      offset: Offset(0, -6),
    ),
  ];
}

/// Plus Jakarta Sans, bundled with this package under the Open Font License,
/// on every platform. One typeface on iOS and Android is what makes the two
/// builds read as one brand; the system font would split it in half.
class FreshlyType {
  const FreshlyType._();

  static const String family = 'PlusJakartaSans';
  static const String package = 'freshly_core';

  /// The resolved family name, for places that take a raw string
  /// (`ThemeData.fontFamily`) rather than a family plus package.
  static const String resolvedFamily = 'packages/$package/$family';

  /// Geometric sans faces read loose at display sizes. Tighten the big type,
  /// leave body copy alone.
  static double tracking(double fontSize) {
    if (fontSize >= 32) return -1.2;
    if (fontSize >= 26) return -0.8;
    if (fontSize >= 20) return -0.5;
    if (fontSize >= 17) return -0.2;
    return 0;
  }

  static TextStyle style(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: family,
        package: package,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking(size),
        height: height,
        color: color,
      );

  static TextTheme textTheme(Color ink, Color muted) => TextTheme(
        displayLarge:
            style(40, weight: FontWeight.w800, height: 1.1, color: ink),
        displayMedium:
            style(34, weight: FontWeight.w800, height: 1.12, color: ink),
        displaySmall:
            style(28, weight: FontWeight.w800, height: 1.15, color: ink),
        headlineLarge:
            style(28, weight: FontWeight.w800, height: 1.15, color: ink),
        headlineMedium:
            style(24, weight: FontWeight.w800, height: 1.2, color: ink),
        headlineSmall:
            style(21, weight: FontWeight.w700, height: 1.25, color: ink),
        titleLarge:
            style(19, weight: FontWeight.w700, height: 1.25, color: ink),
        titleMedium:
            style(16, weight: FontWeight.w700, height: 1.3, color: ink),
        titleSmall:
            style(14, weight: FontWeight.w700, height: 1.35, color: ink),
        bodyLarge: style(16, height: 1.45, color: ink),
        bodyMedium: style(14, height: 1.45, color: ink),
        bodySmall: style(13, height: 1.4, color: muted),
        labelLarge: style(16, weight: FontWeight.w700, color: ink),
        labelMedium: style(13, weight: FontWeight.w600, color: muted),
        labelSmall: style(11, weight: FontWeight.w600, color: muted),
      );
}

class FreshlyTheme {
  const FreshlyTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final ink = isDark ? Colors.white : FreshlyColors.ink;
    final muted = isDark ? const Color(0xFF9AA6B6) : FreshlyColors.inkSubtle;
    final page = isDark ? const Color(0xFF080B12) : FreshlyColors.canvas;
    final surface =
        isDark ? FreshlyColors.obsidianRaised : FreshlyColors.surface;
    final field = isDark ? const Color(0xFF1C2330) : FreshlyColors.field;
    final line = isDark ? const Color(0xFF242C3A) : FreshlyColors.line;
    // The brand green as a readable colour: jade on light, mint on dark.
    final accentText = isDark ? FreshlyColors.mint : FreshlyColors.mintDark;

    final scheme = ColorScheme.fromSeed(
      seedColor: FreshlyColors.mint,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? FreshlyColors.mint : FreshlyColors.mintDark,
      onPrimary: isDark ? FreshlyColors.obsidian : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF0E3A2A) : FreshlyColors.mintSoft,
      onPrimaryContainer: isDark ? FreshlyColors.mint : FreshlyColors.mintInk,
      secondary: FreshlyColors.obsidian,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: field,
      surfaceContainerHigh: field,
      surfaceContainerHighest: field,
      outline: line,
      outlineVariant: line,
      error: FreshlyColors.crimson,
    );

    final text = FreshlyType.textTheme(ink, muted);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: FreshlyType.resolvedFamily,
      splashFactory: NoSplash.splashFactory,
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FreshlySpacing.buttonRadius),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.buttonRadius),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle:
            FreshlyType.style(19, weight: FontWeight.w800, color: ink),
      ),
      // CardThemeData, not CardTheme: ThemeData's *Theme slots moved to their
      // matching *ThemeData types in Flutter 3.32.
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(color: line),
        ),
      ),
      // The primary action: a mint slab with obsidian type. Flat, and it dims
      // on press rather than rippling.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
              Size.fromHeight(FreshlySpacing.buttonHeight)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(rounded),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(
              FreshlyType.style(16, weight: FontWeight.w700)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return field;
            if (states.contains(WidgetState.pressed)) {
              return FreshlyColors.mint.withValues(alpha: 0.78);
            }
            return FreshlyColors.mint;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return isDark ? const Color(0xFF5B6675) : FreshlyColors.inkMuted;
            }
            return FreshlyColors.obsidian;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return FreshlyColors.inkMuted;
            }
            return FreshlyColors.obsidian;
          }),
        ),
      ),
      // The confident secondary: obsidian with white type. Used where mint
      // would compete with a mint primary on the same screen.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
              Size.fromHeight(FreshlySpacing.buttonHeight)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(rounded),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(
              FreshlyType.style(16, weight: FontWeight.w700)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return field;
            final base = isDark ? Colors.white : FreshlyColors.obsidian;
            return states.contains(WidgetState.pressed)
                ? base.withValues(alpha: 0.82)
                : base;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return FreshlyColors.inkMuted;
            }
            return isDark ? FreshlyColors.obsidian : Colors.white;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(FreshlySpacing.buttonHeight),
          foregroundColor: ink,
          backgroundColor: surface,
          textStyle: FreshlyType.style(16, weight: FontWeight.w700),
          side: BorderSide(color: line, width: 1.5),
          shape: rounded,
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentText,
          textStyle: FreshlyType.style(15, weight: FontWeight.w700),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ink,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          textStyle: WidgetStatePropertyAll(
              FreshlyType.style(14, weight: FontWeight.w700)),
          shape: WidgetStatePropertyAll(rounded),
          side: WidgetStatePropertyAll(BorderSide(color: line)),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? (isDark ? Colors.white : FreshlyColors.obsidian)
                  : surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? (isDark ? FreshlyColors.obsidian : Colors.white)
                  : muted),
          iconColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? FreshlyColors.mint
                  : muted),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        hintStyle: FreshlyType.style(15, color: FreshlyColors.inkMuted),
        labelStyle: FreshlyType.style(15, color: muted),
        floatingLabelStyle:
            FreshlyType.style(14, weight: FontWeight.w600, color: accentText),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(accentText, 2),
        errorBorder: inputBorder(FreshlyColors.crimson, 1.5),
        focusedErrorBorder: inputBorder(FreshlyColors.crimson, 2),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: isDark ? Colors.white : FreshlyColors.obsidian,
        labelStyle: FreshlyType.style(13, weight: FontWeight.w600, color: ink),
        secondaryLabelStyle: FreshlyType.style(13,
            weight: FontWeight.w600,
            color: isDark ? FreshlyColors.obsidian : Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: line),
        checkmarkColor: FreshlyColors.mint,
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? Colors.white : FreshlyColors.obsidian,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? (isDark ? FreshlyColors.obsidian : FreshlyColors.mint)
                  : muted,
            )),
        labelTextStyle:
            WidgetStateProperty.resolveWith((states) => FreshlyType.style(
                  12,
                  weight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected) ? ink : muted,
                )),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 12,
        iconColor: muted,
        titleTextStyle:
            FreshlyType.style(15, weight: FontWeight.w600, color: ink),
        subtitleTextStyle: FreshlyType.style(13, height: 1.4, color: muted),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radius)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? FreshlyColors.mintDark
                : line),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: muted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (isDark ? FreshlyColors.mint : FreshlyColors.obsidian)
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(
            isDark ? FreshlyColors.obsidian : FreshlyColors.mint),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? accentText : muted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentText,
        linearTrackColor: field,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accentText,
        inactiveTrackColor: field,
        thumbColor: isDark ? FreshlyColors.mint : FreshlyColors.obsidian,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: FreshlyColors.obsidian,
        contentTextStyle:
            FreshlyType.style(14, weight: FontWeight.w600, color: Colors.white),
        actionTextColor: FreshlyColors.mint,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.buttonRadius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FreshlySpacing.radiusLarge)),
        titleTextStyle:
            FreshlyType.style(19, weight: FontWeight.w800, color: ink),
        contentTextStyle: FreshlyType.style(15, height: 1.45, color: muted),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(FreshlySpacing.radiusLarge)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: muted,
        indicatorColor: accentText,
        dividerColor: line,
        labelStyle: FreshlyType.style(14, weight: FontWeight.w700),
        unselectedLabelStyle: FreshlyType.style(14, weight: FontWeight.w500),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: FreshlyColors.obsidian,
        foregroundColor: FreshlyColors.mint,
        elevation: 0,
        shape: StadiumBorder(),
      ),
    );
  }
}
