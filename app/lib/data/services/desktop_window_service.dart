import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/core/strings/app_strings.dart';
import 'prefs_service.dart';

/// Owns the desktop window itself (Windows/Linux only) — the companion-pane
/// geometry from kb/platform-desktop.md's "Desktop companion layout":
/// ~400×640 docked near the bottom-right of the work area, resizable down to
/// 360×480, with size/position/always-on-top remembered across launches.
///
/// Every member is a no-op off desktop so callers (main.dart, the home
/// screen's pin button) can stay platform-agnostic — Android never sees any
/// of this, exactly like [KehaiForegroundTask] is a no-op off Android.
class DesktopWindowService with WindowListener {
  DesktopWindowService._();

  static final DesktopWindowService instance = DesktopWindowService._();

  /// Locked in kb/platform-desktop.md — a phone-shaped pane that sits beside
  /// your work, not a stretched-out phone app.
  static const Size defaultSize = Size(400, 640);
  static const Size minimumSize = Size(360, 480);

  /// Breathing room between the window and the corner of the work area, so
  /// it reads as "docked next to things" rather than jammed into the corner.
  static const double screenMargin = 24;

  /// Test seam: widget tests run on the Linux VM, where the real check would
  /// say "yes, desktop" and then blow up on the missing method channel.
  @visibleForTesting
  static bool? debugIsSupported;

  static bool get isSupported =>
      debugIsSupported ?? (!kIsWeb && (Platform.isWindows || Platform.isLinux));

  /// Whether the window is currently pinned above other windows. Listened to
  /// by the pin button; kept in sync with the platform after every toggle.
  final ValueNotifier<bool> alwaysOnTop = ValueNotifier<bool>(false);

  PrefsService? _prefs;
  Timer? _persistDebounce;
  bool _ready = false;

  /// Call once from `main()` **before** `runApp`, after
  /// `WidgetsFlutterBinding.ensureInitialized()`. Restores the remembered
  /// geometry (or docks bottom-right on first run) and then shows the window.
  ///
  /// Never throws: a compositor that refuses any of this (Wayland is picky
  /// about position in particular) should cost us a debug line, not a launch.
  Future<void> bootstrap() async {
    if (!isSupported || _ready) return;
    try {
      await windowManager.ensureInitialized();
      final prefs = _prefs = await PrefsService.create();

      final saved = _sanitize(prefs.windowBounds);
      final size = saved?.size ?? defaultSize;

      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: size,
          minimumSize: minimumSize,
          title: AppStrings.appName,
          // We draw our own chrome (KehaiTitleBar) — the whole app is one
          // Win95-parody window, so an OS title bar on top of ours would be
          // two frames deep.
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        ),
      );
      await windowManager.setPosition(
        saved?.topLeft ?? await _dockedBottomRight(size),
      );
      if (prefs.windowAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
        alwaysOnTop.value = true;
      }
      await windowManager.show();
      await windowManager.focus();
      if (prefs.windowMaximized) await windowManager.maximize();

      _ready = true;
      windowManager.addListener(this);
    } catch (error, stack) {
      debugPrint('window setup skipped: $error\n$stack');
    }
  }

  /// Flips the always-on-top pin. Honest about the platform: on Windows this
  /// genuinely raises the window, on Wayland the compositor may accept the
  /// call and quietly do nothing (see kb/platform-desktop.md — Flutter has no
  /// supported topmost path there), which is what the tooltip says.
  Future<void> toggleAlwaysOnTop() async {
    if (!isSupported) return;
    final next = !alwaysOnTop.value;
    try {
      await windowManager.setAlwaysOnTop(next);
      alwaysOnTop.value = await windowManager.isAlwaysOnTop();
    } catch (error) {
      debugPrint('always-on-top toggle failed: $error');
      alwaysOnTop.value = next;
    }
    await _prefs?.setWindowAlwaysOnTop(alwaysOnTop.value);
  }

  /// Title-bar controls. Each is fire-and-forget and swallows platform
  /// failures: a compositor that won't minimize us shouldn't take the app
  /// down with it.
  Future<void> minimize() => _guard(windowManager.minimize);

  Future<void> close() => _guard(windowManager.close);

  /// Double-clicking the title bar, the Win95 way.
  Future<void> toggleMaximize() => _guard(() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  });

  /// Called on pan-start over the title bar; the compositor takes over the
  /// drag from there.
  Future<void> startDragging() => _guard(windowManager.startDragging);

  Future<void> _guard(Future<void> Function() action) async {
    if (!isSupported) return;
    try {
      await action();
    } catch (error) {
      debugPrint('window command failed: $error');
    }
  }

  @override
  void onWindowResized() => _schedulePersist();

  @override
  void onWindowMoved() => _schedulePersist();

  @override
  void onWindowMaximize() {
    unawaited(_prefs?.setWindowMaximized(true));
  }

  @override
  void onWindowUnmaximize() {
    unawaited(_prefs?.setWindowMaximized(false));
    _schedulePersist();
  }

  /// Resize/move events arrive in bursts while dragging; write once the user
  /// has settled instead of hammering shared_preferences every frame.
  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), _persistBounds);
  }

  Future<void> _persistBounds() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      // A maximized window's bounds are the screen's, not the user's chosen
      // pane size — remember the flag instead (see onWindowMaximize) so the
      // restored-down size survives.
      if (await windowManager.isMaximized()) return;
      await prefs.setWindowBounds(await windowManager.getBounds());
    } catch (error) {
      debugPrint('window bounds not saved: $error');
    }
  }

  Future<Offset> _dockedBottomRight(Size size) async {
    final corner = await calcWindowPosition(size, Alignment.bottomRight);
    return Offset(corner.dx - screenMargin, corner.dy - screenMargin);
  }

  /// Guards against a remembered position from a monitor that no longer
  /// exists (or a garbage value): anything wildly off-canvas is dropped and
  /// we re-dock instead of opening the window somewhere invisible.
  Rect? _sanitize(Rect? bounds) {
    if (bounds == null) return null;
    final values = [bounds.left, bounds.top, bounds.width, bounds.height];
    if (values.any((v) => !v.isFinite)) return null;
    if (bounds.width < minimumSize.width ||
        bounds.height < minimumSize.height) {
      return null;
    }
    if (bounds.left < -20000 ||
        bounds.top < -20000 ||
        bounds.left > 20000 ||
        bounds.top > 20000) {
      return null;
    }
    return bounds;
  }
}
