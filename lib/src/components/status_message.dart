import 'package:flutter/material.dart';
import 'package:burlmd/src/design/burl_theme.dart';

/// Shows one transient status message on the nearest [Scaffold]'s SnackBar,
/// replacing whatever message is currently showing.
///
/// Shared by the lifecycle-outcome reporter (`report` in
/// `workspace_tree.dart`) and the rescan listener (`workspace.dart`) so both
/// surfaces report identically: hide-then-show, so a rapid sequence of
/// outcomes (a refusal followed by a rescan failure) cannot queue up into a
/// stack of stale snack bars.
void showStatusMessage(BuildContext context, String message) {
  final colors =
      Theme.of(context).extension<BurlColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? BurlColors.dark
          : BurlColors.light);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: colors.surfaceRaised,
        content: Text(message, style: TextStyle(color: colors.textPrimary)),
      ),
    );
}
