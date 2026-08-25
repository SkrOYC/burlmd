import 'package:burlmd/src/design/burl_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the user's in-session editor presentation preferences.
///
/// Theme tokens and the immutable preference value remain in the design
/// module; this provider is intentionally kept with the other application
/// state seams.
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
