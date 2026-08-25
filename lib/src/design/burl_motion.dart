import 'package:flutter/material.dart';

/// The intentionally short motion vocabulary used by Burl's desktop chrome.
///
/// These transitions only affect painting and transforms. They never animate a
/// pane's dimensions, which keeps the editor's layout stable while a shell
/// surface is entering.
abstract final class BurlMotion {
  static const overlay = Duration(milliseconds: 120);
  static const row = Duration(milliseconds: 100);
  static const chrome = Duration(milliseconds: 150);
  static const focus = Duration(milliseconds: 200);
  static const drawer = overlay;
  static const theme = Duration(milliseconds: 150);
  static const spinner = Duration(seconds: 1);

  static const enterCurve = Cubic(0.16, 1, 0.3, 1);

  static bool isReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration standard) =>
      isReduced(context) ? Duration.zero : standard;

  static Offset offset(BuildContext context, Offset standard) =>
      isReduced(context) ? Offset.zero : standard;

  static double scale(BuildContext context, double standard) =>
      isReduced(context) ? 1 : standard;
}

/// Fades and translates an entering overlay without changing its layout box.
///
/// A zero-duration, zero-translation result is used for the platform's
/// reduced-motion preference. The child remains in the tree throughout, so
/// focus, keyboard handlers, and scrim hit testing are not interrupted.
class BurlSlideFadeEntrance extends StatefulWidget {
  const BurlSlideFadeEntrance({
    super.key,
    required this.child,
    this.beginOffset = Offset.zero,
    this.duration = BurlMotion.drawer,
  });

  final Widget child;
  final Offset beginOffset;
  final Duration duration;

  @override
  State<BurlSlideFadeEntrance> createState() => _BurlSlideFadeEntranceState();
}

/// Fades a stationary backdrop while a sibling pane uses [BurlSlideFadeEntrance].
class BurlFadeEntrance extends StatefulWidget {
  const BurlFadeEntrance({
    super.key,
    required this.child,
    this.duration = BurlMotion.overlay,
  });

  final Widget child;
  final Duration duration;

  @override
  State<BurlFadeEntrance> createState() => _BurlFadeEntranceState();
}

class _BurlFadeEntranceState extends State<BurlFadeEntrance> {
  var _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entered = BurlMotion.isReduced(context) || _entered;
    return IgnorePointer(
      ignoring: !entered,
      child: AnimatedOpacity(
        opacity: entered ? 1 : 0,
        duration: BurlMotion.duration(context, widget.duration),
        curve: BurlMotion.enterCurve,
        child: widget.child,
      ),
    );
  }
}

class _BurlSlideFadeEntranceState extends State<BurlSlideFadeEntrance> {
  var _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = BurlMotion.isReduced(context);
    final entered = reduced || _entered;
    final duration = BurlMotion.duration(context, widget.duration);
    return IgnorePointer(
      ignoring: !entered,
      child: AnimatedOpacity(
        opacity: entered ? 1 : 0,
        duration: duration,
        curve: BurlMotion.enterCurve,
        child: AnimatedSlide(
          offset: entered
              ? Offset.zero
              : BurlMotion.offset(context, widget.beginOffset),
          duration: duration,
          curve: BurlMotion.enterCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and scales a dialog-like overlay from 98% to its resting size.
class BurlScaleFadeEntrance extends StatefulWidget {
  const BurlScaleFadeEntrance({
    super.key,
    required this.child,
    this.duration = BurlMotion.overlay,
  });

  final Widget child;
  final Duration duration;

  @override
  State<BurlScaleFadeEntrance> createState() => _BurlScaleFadeEntranceState();
}

class _BurlScaleFadeEntranceState extends State<BurlScaleFadeEntrance> {
  var _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = BurlMotion.isReduced(context);
    final entered = reduced || _entered;
    final duration = BurlMotion.duration(context, widget.duration);
    return IgnorePointer(
      ignoring: !entered,
      child: AnimatedOpacity(
        opacity: entered ? 1 : 0,
        duration: duration,
        curve: BurlMotion.enterCurve,
        child: AnimatedScale(
          scale: entered ? 1 : BurlMotion.scale(context, .98),
          duration: duration,
          curve: BurlMotion.enterCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Applies the shell's restrained theme interpolation beneath [MaterialApp].
class BurlThemeTransition extends StatelessWidget {
  const BurlThemeTransition({
    super.key,
    required this.theme,
    required this.child,
  });

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedTheme(
    data: theme,
    duration: BurlMotion.duration(context, BurlMotion.theme),
    curve: BurlMotion.enterCurve,
    child: child,
  );
}

/// Paint-only sync indicator with a deterministic reduced-motion state.
class BurlSyncSpinner extends StatelessWidget {
  const BurlSyncSpinner({super.key, required this.turns, required this.child});
  final Animation<double> turns;
  final Widget child;

  @override
  Widget build(BuildContext context) => BurlMotion.isReduced(context)
      ? KeyedSubtree(key: const ValueKey('sync-spinner-stopped'), child: child)
      : RotationTransition(
          key: const ValueKey('sync-spinner'),
          turns: turns,
          child: child,
        );
}
