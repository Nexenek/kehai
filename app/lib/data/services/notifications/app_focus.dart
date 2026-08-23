import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Answers one question for the notifier: **is the person already looking at
/// Kehai on this device right now?**
///
/// If they are, a notification about something they can see arriving is
/// noise, so [decideNotification] drops it (rule 2 in its doc comment).
///
/// Two independent signals, because neither one alone is right everywhere:
///
/// - **Lifecycle** ([AppLifecycleState.resumed]) is the answer on Android:
///   resumed means the activity is on screen and interactive.
/// - **Window focus** is the answer on desktop, where the app can be fully
///   visible (it's a little always-on-top card — that's the whole design)
///   while you're typing in something else entirely. A visible-but-unfocused
///   mini card is exactly the case where you *do* want the notification.
///
/// On desktop both are consulted and focus wins when it's known: Flutter's
/// desktop lifecycle reporting has historically been uneven across
/// compositors, so a window_manager focus event is the more trustworthy of
/// the two. On Android the window listener is never attached at all.
///
/// This deliberately does NOT touch [DesktopWindowService], which owns the
/// window itself — `window_manager` supports multiple listeners, so this
/// registers its own and stays entirely separable.
class AppFocusTracker with WidgetsBindingObserver, WindowListener {
  AppFocusTracker({@visibleForTesting bool? isDesktopOverride})
    : _isDesktop =
          isDesktopOverride ??
          (!kIsWeb && (Platform.isLinux || Platform.isWindows));

  final bool _isDesktop;

  /// True when Kehai is the thing the user is currently in.
  ///
  /// Starts true: the app is launching *because* someone opened it, and the
  /// wrong direction to be wrong in is "buzzed them about the doodle they're
  /// looking at". A stale-true resolves at the first lifecycle/focus event.
  final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);

  /// Called whenever [isForeground] flips — Android uses this to push the
  /// value down to the background isolate, which is the isolate that
  /// actually raises notifications there (see [KehaiTaskHandler]).
  void Function(bool foreground)? onChanged;

  bool _started = false;

  /// Whether window_manager has ever told us anything. Until it has, desktop
  /// falls back to the lifecycle signal — otherwise a compositor that never
  /// delivers focus events would leave [isForeground] stuck at its initial
  /// `true` forever, and this device would silently never notify. Once a
  /// real focus/blur arrives it takes over for good, because it's the more
  /// accurate answer (a visible-but-unfocused mini card is exactly the case
  /// lifecycle gets wrong).
  bool _sawWindowEvent = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    if (_isDesktop) {
      try {
        windowManager.addListener(this);
      } catch (error) {
        // No window_manager binding (tests, or a platform without a runner)
        // — lifecycle alone still gives a usable answer.
        debugPrint('window focus tracking unavailable: $error');
      }
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    if (_isDesktop) {
      try {
        windowManager.removeListener(this);
      } catch (_) {
        // Never registered — nothing to remove.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Desktop: window_manager's focus/blur events are authoritative once
    // they start arriving — a `hidden`/`inactive` lifecycle tick from a
    // compositor quirk shouldn't override them. Before then, lifecycle is
    // all we have and is better than nothing (see [_sawWindowEvent]).
    if (_isDesktop && _sawWindowEvent) return;
    _set(state == AppLifecycleState.resumed);
  }

  @override
  void onWindowFocus() => _setFromWindow(true);

  @override
  void onWindowBlur() => _setFromWindow(false);

  /// Collapsing to the tray is "not looking at it" even though the process
  /// stays alive and the window may still exist.
  @override
  void onWindowMinimize() => _setFromWindow(false);

  @override
  void onWindowRestore() => _setFromWindow(true);

  void _setFromWindow(bool value) {
    _sawWindowEvent = true;
    _set(value);
  }

  void _set(bool value) {
    if (isForeground.value == value) return;
    isForeground.value = value;
    onChanged?.call(value);
  }

  @visibleForTesting
  void setForegroundForTest(bool value) => _set(value);

  void dispose() {
    stop();
    isForeground.dispose();
  }
}
