import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Font families embedded solely for the deterministic visual-parity fixture.
///
/// These names deliberately differ from Flutter's built-in `Roboto` family,
/// whose bundled, static files are an older release than the prototype's
/// Linux-resolved variable Roboto face.
const burlPrototypeSansFontFamily = 'BurlPrototypeSans';
const burlPrototypeMonoFontFamily = 'BurlPrototypeMono';

const burlPrototypeSansFallback = <String>['Noto Sans', 'Noto Color Emoji'];

const burlPrototypeMonoFallback = <String>[
  'Noto Sans Mono',
  'Noto Color Emoji',
];

enum BurlThemePreference { system, light, dark }

enum BurlFontScale {
  compact(14, 1.625, 'Compact'),
  standard(16, 1.68, 'Standard'),
  comfortable(18, 1.72, 'Comfortable'),
  spacious(20, 1.75, 'Large');

  const BurlFontScale(this.size, this.height, this.label);

  final double size;
  final double height;
  final String label;
}

enum BurlMeasure {
  narrow(440, '55ch · Narrow reading'),
  standard(520, '65ch · Standard prose'),
  wide(600, '75ch · Wide'),
  technical(680, '85ch · Code & tables'),
  full(double.infinity, 'Full width');

  const BurlMeasure(this.maxWidth, this.label);

  final double maxWidth;
  final String label;
}

enum BurlPlatformChrome { macos, linux, minimal }

@immutable
class BurlPreferences {
  const BurlPreferences({
    this.theme = BurlThemePreference.system,
    this.fontScale = BurlFontScale.standard,
    this.measure = BurlMeasure.standard,
    this.platformChrome = BurlPlatformChrome.macos,
    this.focusMode = false,
  });

  final BurlThemePreference theme;
  final BurlFontScale fontScale;
  final BurlMeasure measure;
  final BurlPlatformChrome platformChrome;
  final bool focusMode;

  /// The host window owns its titlebar on Linux, so drawing a second set of
  /// macOS traffic controls there is misleading by default. The preference
  /// remains explicit and can still be changed in the drawer.
  factory BurlPreferences.defaults() => BurlPreferences(
    platformChrome: defaultTargetPlatform == TargetPlatform.linux
        ? BurlPlatformChrome.minimal
        : BurlPlatformChrome.macos,
  );

  BurlPreferences copyWith({
    BurlThemePreference? theme,
    BurlFontScale? fontScale,
    BurlMeasure? measure,
    BurlPlatformChrome? platformChrome,
    bool? focusMode,
  }) => BurlPreferences(
    theme: theme ?? this.theme,
    fontScale: fontScale ?? this.fontScale,
    measure: measure ?? this.measure,
    platformChrome: platformChrome ?? this.platformChrome,
    focusMode: focusMode ?? this.focusMode,
  );
}

class BurlPreferencesController extends Notifier<BurlPreferences> {
  @override
  BurlPreferences build() => BurlPreferences.defaults();

  void setTheme(BurlThemePreference value) =>
      state = state.copyWith(theme: value);

  void setFontScale(BurlFontScale value) =>
      state = state.copyWith(fontScale: value);

  void setMeasure(BurlMeasure value) => state = state.copyWith(measure: value);

  void setPlatformChrome(BurlPlatformChrome value) =>
      state = state.copyWith(platformChrome: value);

  void setFocusMode(bool value) => state = state.copyWith(focusMode: value);
}

final burlPreferencesProvider =
    NotifierProvider<BurlPreferencesController, BurlPreferences>(
      BurlPreferencesController.new,
    );

extension on BurlThemePreference {
  ThemeMode get materialMode => switch (this) {
    BurlThemePreference.system => ThemeMode.system,
    BurlThemePreference.light => ThemeMode.light,
    BurlThemePreference.dark => ThemeMode.dark,
  };
}

ThemeMode materialThemeMode(BurlThemePreference preference) =>
    preference.materialMode;

@immutable
class BurlColors extends ThemeExtension<BurlColors> {
  const BurlColors({
    required this.app,
    required this.sidebar,
    required this.editor,
    required this.surface,
    required this.surfaceRaised,
    required this.hover,
    required this.active,
    required this.focusedBlock,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSubtle,
    required this.accentBorder,
    required this.review,
    required this.reviewSubtle,
    required this.syncConnected,
    required this.syncOffline,
    required this.syncError,
    required this.diffAddBackground,
    required this.diffAddBorder,
    required this.diffDeleteBackground,
    required this.diffDeleteBorder,
  });

  final Color app;
  final Color sidebar;
  final Color editor;
  final Color surface;
  final Color surfaceRaised;
  final Color hover;
  final Color active;
  final Color focusedBlock;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSubtle;
  final Color accentBorder;
  final Color review;
  final Color reviewSubtle;
  final Color syncConnected;
  final Color syncOffline;
  final Color syncError;
  final Color diffAddBackground;
  final Color diffAddBorder;
  final Color diffDeleteBackground;
  final Color diffDeleteBorder;

  static const light = BurlColors(
    app: Color(0xfffaf9f6),
    sidebar: Color(0xfff3f2ee),
    editor: Color(0xffffffff),
    surface: Color(0xffffffff),
    surfaceRaised: Color(0xfff9f8f4),
    hover: Color(0xffeae8e2),
    active: Color(0xff262522),
    focusedBlock: Color(0xfff4f3ef),
    borderSubtle: Color(0xffe6e4dd),
    borderStrong: Color(0xffd2cfc6),
    textPrimary: Color(0xff1e1e1c),
    textSecondary: Color(0xff5a5852),
    textMuted: Color(0xff8e8b82),
    accent: Color(0xff3f5b46),
    accentSubtle: Color(0xffedf4ee),
    accentBorder: Color(0xffbccfc0),
    review: Color(0xff706b5e),
    reviewSubtle: Color(0xfff9f6f0),
    syncConnected: Color(0xff3f5b46),
    syncOffline: Color(0xff8e8b82),
    syncError: Color(0xffb91c1c),
    diffAddBackground: Color(0xfff0fdf4),
    diffAddBorder: Color(0xff16a34a),
    diffDeleteBackground: Color(0xfffef2f2),
    diffDeleteBorder: Color(0xffdc2626),
  );

  static const dark = BurlColors(
    app: Color(0xff151517),
    sidebar: Color(0xff111113),
    editor: Color(0xff18181b),
    surface: Color(0xff202024),
    surfaceRaised: Color(0xff222228),
    hover: Color(0xff27272d),
    active: Color(0xffe4e4e7),
    focusedBlock: Color(0xff222227),
    borderSubtle: Color(0xff27272c),
    borderStrong: Color(0xff3e3e47),
    textPrimary: Color(0xfff4f4f5),
    textSecondary: Color(0xffa1a1aa),
    textMuted: Color(0xff71717a),
    accent: Color(0xff86a789),
    accentSubtle: Color(0xff1c261e),
    accentBorder: Color(0xff394a37),
    review: Color(0xffb8a88a),
    reviewSubtle: Color(0xff2a2318),
    syncConnected: Color(0xff86a789),
    syncOffline: Color(0xff71717a),
    syncError: Color(0xfff87171),
    diffAddBackground: Color(0xff12281a),
    diffAddBorder: Color(0xff22c55e),
    diffDeleteBackground: Color(0xff2c1518),
    diffDeleteBorder: Color(0xffef4444),
  );

  @override
  BurlColors copyWith({
    Color? app,
    Color? sidebar,
    Color? editor,
    Color? surface,
    Color? surfaceRaised,
    Color? hover,
    Color? active,
    Color? focusedBlock,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSubtle,
    Color? accentBorder,
    Color? review,
    Color? reviewSubtle,
    Color? syncConnected,
    Color? syncOffline,
    Color? syncError,
    Color? diffAddBackground,
    Color? diffAddBorder,
    Color? diffDeleteBackground,
    Color? diffDeleteBorder,
  }) => BurlColors(
    app: app ?? this.app,
    sidebar: sidebar ?? this.sidebar,
    editor: editor ?? this.editor,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    hover: hover ?? this.hover,
    active: active ?? this.active,
    focusedBlock: focusedBlock ?? this.focusedBlock,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentSubtle: accentSubtle ?? this.accentSubtle,
    accentBorder: accentBorder ?? this.accentBorder,
    review: review ?? this.review,
    reviewSubtle: reviewSubtle ?? this.reviewSubtle,
    syncConnected: syncConnected ?? this.syncConnected,
    syncOffline: syncOffline ?? this.syncOffline,
    syncError: syncError ?? this.syncError,
    diffAddBackground: diffAddBackground ?? this.diffAddBackground,
    diffAddBorder: diffAddBorder ?? this.diffAddBorder,
    diffDeleteBackground: diffDeleteBackground ?? this.diffDeleteBackground,
    diffDeleteBorder: diffDeleteBorder ?? this.diffDeleteBorder,
  );

  @override
  BurlColors lerp(covariant BurlColors? other, double t) {
    if (other == null) return this;
    return BurlColors(
      app: Color.lerp(app, other.app, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      editor: Color.lerp(editor, other.editor, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      active: Color.lerp(active, other.active, t)!,
      focusedBlock: Color.lerp(focusedBlock, other.focusedBlock, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      review: Color.lerp(review, other.review, t)!,
      reviewSubtle: Color.lerp(reviewSubtle, other.reviewSubtle, t)!,
      syncConnected: Color.lerp(syncConnected, other.syncConnected, t)!,
      syncOffline: Color.lerp(syncOffline, other.syncOffline, t)!,
      syncError: Color.lerp(syncError, other.syncError, t)!,
      diffAddBackground: Color.lerp(
        diffAddBackground,
        other.diffAddBackground,
        t,
      )!,
      diffAddBorder: Color.lerp(diffAddBorder, other.diffAddBorder, t)!,
      diffDeleteBackground: Color.lerp(
        diffDeleteBackground,
        other.diffDeleteBackground,
        t,
      )!,
      diffDeleteBorder: Color.lerp(
        diffDeleteBorder,
        other.diffDeleteBorder,
        t,
      )!,
    );
  }
}

extension BurlThemeContext on BuildContext {
  BurlColors get burlColors =>
      Theme.of(this).extension<BurlColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? BurlColors.dark
          : BurlColors.light);
}

ThemeData buildBurlTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? BurlColors.dark
      : BurlColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
        primary: colors.accent,
        surface: colors.surface,
        error: colors.syncError,
      ).copyWith(
        onPrimary: brightness == Brightness.dark
            ? colors.editor
            : colors.surface,
        onSurface: colors.textPrimary,
        surfaceContainerHighest: colors.surfaceRaised,
        outline: colors.borderStrong,
        outlineVariant: colors.borderSubtle,
      );
  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.app,
    canvasColor: colors.surface,
    dividerColor: colors.borderSubtle,
    hoverColor: colors.hover,
    focusColor: colors.accentSubtle,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    useMaterial3: true,
    extensions: [colors],
  );
  final textTheme = base.textTheme.apply(
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );
  return base.copyWith(
    textTheme: textTheme.copyWith(
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.45),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: IconThemeData(color: colors.textSecondary, size: 16),
    dividerTheme: DividerThemeData(
      color: colors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderStrong),
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      textStyle: TextStyle(color: colors.textPrimary, fontSize: 11),
      waitDuration: const Duration(milliseconds: 450),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.editor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
      border: _inputBorder(colors.borderSubtle),
      enabledBorder: _inputBorder(colors.borderSubtle),
      focusedBorder: _inputBorder(colors.accentBorder),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceRaised,
      contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.borderStrong),
        borderRadius: BorderRadius.circular(7),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
  );
}

/// Applies prototype-resolved faces only to the visual-parity fixture.
/// Production screens continue to use [buildBurlTheme] directly.
ThemeData buildBurlPrototypeFixtureTheme(Brightness brightness) {
  final base = buildBurlTheme(brightness);
  TextStyle sans(double size, double height, FontWeight weight, Color color) =>
      TextStyle(
        fontFamily: burlPrototypeSansFontFamily,
        fontFamilyFallback: burlPrototypeSansFallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color,
        fontVariations: [
          FontVariation('wght', weight.value.toDouble()),
          const FontVariation('wdth', 100),
        ],
      );
  final color = brightness == Brightness.dark
      ? const Color(0xffd4d4d4)
      : const Color(0xff262522);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: sans(15, 1.65, FontWeight.w400, color),
      bodyMedium: sans(14, 1.5, FontWeight.w400, color),
      bodySmall: sans(12, 16 / 12, FontWeight.w400, color),
      labelLarge: sans(12, 16 / 12, FontWeight.w400, color),
      labelMedium: sans(11, 15 / 11, FontWeight.w400, color),
      labelSmall: sans(10, 14 / 10, FontWeight.w400, color),
      titleMedium: sans(20, 28 / 20, FontWeight.w600, color),
      titleSmall: sans(12, 16 / 12, FontWeight.w600, color),
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: burlPrototypeSansFontFamily,
      fontFamilyFallback: burlPrototypeSansFallback,
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(6),
  borderSide: BorderSide(color: color),
);
