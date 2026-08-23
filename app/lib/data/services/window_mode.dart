import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The two shapes the one desktop window takes.
///
/// Flutter desktop is single-window, so "the little always-there card" and
/// "the full companion panel" are the same OS window wearing different
/// sizes and content — see kb/platform-desktop.md.
enum WindowMode {
  /// The resting state: a small, frameless, always-on-top card showing the
  /// partner's mood and ambient line. Clicking it expands.
  mini,

  /// The companion panel (or the wide spread) with our title bar.
  expanded,
}

/// Where the app should start.
///
/// A paired, logged-in user gets the little window — Kehai's whole point is
/// being quietly present, not occupying the screen. Anyone still in
/// onboarding gets the panel, because you cannot type a server address into
/// a 240×150 card.
WindowMode initialWindowMode({required bool paired}) =>
    paired ? WindowMode.mini : WindowMode.expanded;

/// Which corner of [from] to hold still while resizing to [to].
///
/// The window should look like it grew out of the card the user clicked, so
/// we keep the nearest corner pinned: a card living bottom-right grows up
/// and to the left, one at the top-left grows down and to the right.
Rect anchorResize({
  required Rect from,
  required Size to,
  required Rect workArea,
}) {
  final keepRightEdge = from.center.dx > workArea.center.dx;
  final keepBottomEdge = from.center.dy > workArea.center.dy;

  var left = keepRightEdge ? from.right - to.width : from.left;
  var top = keepBottomEdge ? from.bottom - to.height : from.top;

  // Clamp into the work area — shifted, never resized. A window bigger than
  // the work area simply starts at its top-left corner.
  left = _clamp(left, workArea.left, workArea.right - to.width);
  top = _clamp(top, workArea.top, workArea.bottom - to.height);

  return Rect.fromLTWH(left, top, to.width, to.height);
}

double _clamp(double value, double min, double max) {
  if (max < min) return min;
  return value < min ? min : (value > max ? max : value);
}

/// The platform half of a mode change. [DesktopWindowService] implements it
/// against window_manager; tests use a fake, which is what keeps the
/// transitions below testable without a window.
abstract interface class WindowModeEffects {
  /// Shrink to the little card: mini size, always-on-top, no taskbar entry.
  Future<void> applyMini();

  /// Grow back to the panel, anchored on the card's corner.
  Future<void> applyExpanded();

  /// Actually exit — the only route out of the app.
  Future<void> applyQuit();
}

/// Owns which [WindowMode] we're in and runs the transitions one at a time.
///
/// The important rule lives here: **closing never quits**. ♥ on our title
/// bar and ★ both collapse to the little window, exactly like every tray
/// app; the only thing that ends the process is "quit for real" in the tray
/// menu. Anything else would make a companion app that vanishes the moment
/// you tidy your screen.
class WindowModeController extends ChangeNotifier {
  WindowModeController({
    required this.effects,
    WindowMode initial = WindowMode.expanded,
  }) : _mode = initial;

  /// The window this controller drives.
  final WindowModeEffects effects;

  WindowMode _mode;
  WindowMode get mode => _mode;

  bool get isMini => _mode == WindowMode.mini;

  bool _quitting = false;

  /// True once "quit for real" has been taken — the app is on its way out.
  bool get isQuitting => _quitting;

  /// Transitions are serialized: a double-click on the tray icon must not
  /// interleave two resize/reposition sequences on the same window.
  Future<void> _queue = Future<void>.value();

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    // Keep the chain alive even if one step throws.
    _queue = next.catchError((_) {});
    return next;
  }

  /// Goes to [mode], or does nothing if we're already there.
  Future<void> setMode(WindowMode mode) {
    if (_quitting || mode == _mode) return Future<void>.value();
    _mode = mode;
    notifyListeners();
    return _serial(
      mode == WindowMode.mini ? effects.applyMini : effects.applyExpanded,
    );
  }

  Future<void> expand() => setMode(WindowMode.expanded);

  Future<void> collapse() => setMode(WindowMode.mini);

  /// The tray icon's left click, and the mini card's tap.
  Future<void> toggle() =>
      setMode(isMini ? WindowMode.expanded : WindowMode.mini);

  /// ♥ on our title bar. Collapses — it does not, and must not, quit.
  Future<void> closeToMini() => collapse();

  /// ★ on our title bar. A tray app has nowhere to minimize *to*, so this
  /// collapses as well rather than dropping the window into a taskbar the
  /// app isn't even listed in.
  Future<void> minimizeToMini() => collapse();

  /// "quit for real" — the single exit.
  Future<void> quit() {
    if (_quitting) return Future<void>.value();
    _quitting = true;
    notifyListeners();
    return _serial(effects.applyQuit);
  }
}
