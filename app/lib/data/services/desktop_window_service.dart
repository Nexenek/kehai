import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/core/strings/app_strings.dart';
import 'oled_care.dart';
import 'prefs_service.dart';
import 'window_mode.dart';

/// Owns the desktop window itself (Windows/Linux only) — the companion-pane
/// geometry from kb/platform-desktop.md's "Desktop companion layout":
/// ~400×640 docked near the bottom-right of the work area, resizable down to
/// 360×480, with size/position/always-on-top remembered across launches.
///
/// Every member is a no-op off desktop so callers (main.dart, the home
/// screen's pin button) can stay platform-agnostic — Android never sees any
/// of this, exactly like [KehaiForegroundTask] is a no-op off Android.
class DesktopWindowService with WindowListener implements WindowModeEffects {
  DesktopWindowService._();

  static final DesktopWindowService instance = DesktopWindowService._();

  /// Locked in kb/platform-desktop.md — a phone-shaped pane that sits beside
  /// your work, not a stretched-out phone app.
  static const Size defaultSize = Size(400, 640);
  static const Size minimumSize = Size(360, 480);

  /// The little always-there card (kb/platform-desktop.md). Fixed size —
  /// it's a glanceable object, not a pane you arrange.
  static const Size miniSize = Size(240, 150);

  /// Breathing room between the window and the corner of the work area, so
  /// it reads as "docked next to things" rather than jammed into the corner.
  static const double screenMargin = 24;

  /// The `app.kehai/window#setTransparent` channel: asks the runner to make
  /// the OS window itself see-through (mini mode) or opaque again (expanded
  /// mode). Windows answers via `DwmExtendFrameIntoClientArea`
  /// (windows/runner/transparency_channel.cpp); Linux answers via an RGBA
  /// visual on the GtkWindow, only when the screen is composited
  /// (linux/runner/my_application.cc).
  static const MethodChannel _windowChannel = MethodChannel('app.kehai/window');

  /// Whether the window behind the mini card is genuinely see-through right
  /// now, in which case the card drops its opaque fill and gets
  /// pixel-stepped corners (kb/platform-desktop.md's degrade for a
  /// non-compositing desktop).
  ///
  /// Runner-side C++ exists on both platforms to make this genuinely
  /// work — Windows via `DwmExtendFrameIntoClientArea`
  /// (windows/runner/transparency_channel.cpp), Linux via an RGBA visual
  /// (linux/runner/my_application.cc), both capability-checked at runtime
  /// through [setMiniTransparency] rather than assumed.
  ///
  /// [applyMini] doesn't call that check at all any more, though, and this
  /// stays hard-coded `false` on both platforms: user preference
  /// (2026-08-24) is that the pastel mini card looks identical on Windows
  /// and Linux, and Windows' own attempt already paints the system accent
  /// colour instead of clearing (user-verified 2026-08-23) — worse than the
  /// opaque card it would replace. [MiniPartnerWindow]'s opaque pastel
  /// fallback is what every mini card shows today; genuine transparency is
  /// one `await setMiniTransparency(true)` away in [applyMini] whenever
  /// that changes, not a rewrite — the capability probe stays fully wired.
  final ValueNotifier<bool> wantsTransparentMini = ValueNotifier<bool>(false);

  /// Test seam: widget tests run on the Linux VM, where the real check would
  /// say "yes, desktop" and then blow up on the missing method channel.
  @visibleForTesting
  static bool? debugIsSupported;

  static bool get isSupported =>
      debugIsSupported ?? (!kIsWeb && (Platform.isWindows || Platform.isLinux));

  /// Whether the window is currently pinned above other windows. Listened to
  /// by the pin button; kept in sync with the platform after every toggle.
  ///
  /// The mini card is always on top regardless — being glanceable is the
  /// whole job — so this only governs the expanded panel.
  final ValueNotifier<bool> alwaysOnTop = ValueNotifier<bool>(false);

  /// Which of the two window shapes we're wearing. The UI listens to this;
  /// this service is the [WindowModeEffects] behind it.
  late final WindowModeController windowMode = WindowModeController(
    effects: this,
  );

  /// OLED burn-in protection for the mini card (kb/platform-desktop.md,
  /// tray checkbox in [KehaiTray]) — see oled_care.dart for the actual
  /// nudge/dim logic. The two callbacks are its only touch on the real
  /// window: [_oledCareMoveTo] additionally raises [_oledCareNudging] so
  /// the nudge's own [onWindowMoved] doesn't get mistaken for a user drag
  /// and persisted as a new base (see that listener below).
  late final OledCare oledCare = OledCare(
    moveTo: _oledCareMoveTo,
    setOpacity: (opacity) => _guard(() => windowManager.setOpacity(opacity)),
  );

  /// True for the short window between an [oledCare] nudge asking
  /// window_manager to move and that move's own [onWindowMoved] arriving —
  /// consumed (and cleared) by the very listener call it exists to
  /// intercept. [_nudgeGuardTimer] is a safety net in case a platform ever
  /// fails to deliver that callback at all, so a swallowed flag can never
  /// silently eat a *real* future drag's persist.
  bool _oledCareNudging = false;
  Timer? _nudgeGuardTimer;

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
      // Kehai lives in the tray, in both window states — the taskbar button
      // would be a second, redundant handle on a window you summon from the
      // little heart instead.
      await windowManager.setSkipTaskbar(true);
      await windowManager.show();
      await windowManager.focus();
      if (prefs.windowMaximized) await windowManager.maximize();

      // Windows gets its icon for free — it's compiled into the exe via
      // windows/runner/Runner.rc's IDI_APP_ICON resource
      // (resources/app_icon.ico, generated by tool/generate_tray_icon.py).
      // Linux has no such compiled slot, so it's set at runtime instead;
      // window_manager's own doc comment says "@platforms windows" but the
      // Linux plugin implements setIcon too (gtk_window_set_icon_from_file),
      // and the bundle layout its Dart side assumes — data/flutter_assets
      // next to the executable — is exactly how `flutter build linux` lays
      // things out, so it just works.
      if (Platform.isLinux) {
        try {
          await windowManager.setIcon('assets/icons/kehai_icon.png');
        } catch (error) {
          debugPrint('window icon unavailable: $error');
        }
      }

      _ready = true;
      windowManager.addListener(this);
    } catch (error, stack) {
      debugPrint('window setup skipped: $error\n$stack');
    }
  }

  /// Asks the runner to turn genuine window transparency on or off, and
  /// reports back whether it actually took — never assumed, always the
  /// runner's answer.
  ///
  /// Best-effort and capability-checked, like every other member here: off
  /// desktop, in tests (no runner registered so the channel throws
  /// [MissingPluginException]), on an uncomposited Linux screen, or if the
  /// Windows DWM call itself fails, this returns `false` and
  /// [wantsTransparentMini] stays false. Public (rather than folded into
  /// [applyMini]) so tests can drive the channel round-trip directly
  /// without a real window_manager binding.
  Future<bool> setMiniTransparency(bool enabled) async {
    if (!isSupported) return false;
    try {
      final result = await _windowChannel.invokeMethod<bool>(
        'setTransparent',
        enabled,
      );
      return result ?? false;
    } catch (error) {
      debugPrint('mini transparency unavailable: $error');
      return false;
    }
  }

  /// Called once the app knows whether it has a partner to show: a paired
  /// user's window tucks itself into the little card, everyone else stays on
  /// the panel they're onboarding in.
  Future<void> settleInitialMode({required bool paired}) =>
      windowMode.setMode(initialWindowMode(paired: paired));

  /// Runs just before the process exits (tray teardown). Set by [KehaiTray].
  Future<void> Function()? beforeQuit;

  /// Shrinks to the little always-there card, anchored on the corner the
  /// panel already occupies so it looks like the window folded into it.
  @override
  Future<void> applyMini() => _guard(() async {
    final panel = await windowManager.getBounds();
    if (!await windowManager.isMaximized()) {
      await _prefs?.setWindowBounds(panel);
    } else {
      await windowManager.unmaximize();
    }

    final saved = _prefs?.miniWindowPosition;
    final target =
        saved ??
        anchorResize(
          from: panel,
          to: miniSize,
          workArea: await _workArea(miniSize),
        ).topLeft;

    // Order matters: the size limits have to make room for a 240×150 window
    // before we ask for one, or the resize is clamped to the panel minimum.
    await windowManager.setMinimumSize(miniSize);
    await windowManager.setMaximumSize(miniSize);
    await windowManager.setResizable(false);
    await windowManager.setBounds(null, position: target, size: miniSize);
    // The card is always on top whatever the pin says — a glanceable thing
    // you have to dig for isn't glanceable.
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
    // User preference (2026-08-24): the pastel mini card should look
    // identical on Windows and Linux, so genuine window transparency is
    // switched off everywhere for now — Linux joins the Windows exclusion
    // just above (system-accent blue instead of clearing). The capability
    // check itself is untouched — setMiniTransparency and the runner-side
    // compositor probe (linux/runner/my_application.cc) stay fully wired —
    // this just never calls it, so flipping Linux back on later is the one
    // line `await setMiniTransparency(true)`, not a rewrite.
    wantsTransparentMini.value = false;

    if (_prefs?.oledCareEnabled ?? false) oledCare.start(target);
  });

  /// Grows back into the companion panel from the card's corner.
  @override
  Future<void> applyExpanded() => _guard(() async {
    // The panel is transient — no nudging a window nobody's about to leave
    // sitting for hours, and no dimming it either (see OledCare.stop's doc:
    // this always restores full opacity even without snapping the position,
    // since a dim panel would just be a bug). Re-armed by [applyMini] the
    // next time the card comes back.
    oledCare.stop();
    // The full panel never wears the glassy look — restore opaque before
    // anything else so there's no glassy flash mid-resize.
    wantsTransparentMini.value = false;
    await setMiniTransparency(false);
    final card = await windowManager.getBounds();
    await _prefs?.setMiniWindowPosition(card.topLeft);

    final size = _sanitize(_prefs?.windowBounds)?.size ?? defaultSize;
    final target = anchorResize(
      from: card,
      to: size,
      workArea: await _workArea(size),
    ).topLeft;

    await windowManager.setMaximumSize(_noMaximum);
    await windowManager.setMinimumSize(minimumSize);
    await windowManager.setResizable(true);
    await windowManager.setBounds(null, position: target, size: size);
    await windowManager.setAlwaysOnTop(alwaysOnTop.value);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
    await windowManager.focus();
  });

  /// "quit for real". Everything else in the app collapses instead.
  @override
  Future<void> applyQuit() => _guard(() async {
    _persistDebounce?.cancel();
    _nudgeGuardTimer?.cancel();
    oledCare.dispose();
    await _persistBounds();
    await beforeQuit?.call();
    await windowManager.destroy();
  });

  /// [oledCare]'s only route to actually moving the window: raises
  /// [_oledCareNudging] first so the nudge's own [onWindowMoved] is
  /// recognised and swallowed rather than persisted as a new base position
  /// (see that listener below) — the whole reason a nudge can never drift
  /// the remembered spot. Also used for OledCare's own "snap back to base"
  /// on disable, which is exactly as much "not a user drag" as a nudge is.
  Future<void> _oledCareMoveTo(Offset position) {
    _oledCareNudging = true;
    _nudgeGuardTimer?.cancel();
    // Safety net only: onWindowMoved ordinarily consumes and clears this
    // itself the moment the platform reports the move back. If some
    // platform ever doesn't deliver that callback at all, this is what
    // stops the flag from silently swallowing a real future drag's persist.
    _nudgeGuardTimer = Timer(const Duration(seconds: 5), () {
      _oledCareNudging = false;
    });
    return _guard(() => windowManager.setPosition(position));
  }

  /// Desktop only: flips "oled care" (the tray checkbox backed by
  /// [PrefsService.oledCareEnabled]) live, not just for the next time the
  /// window happens to enter mini mode. Persists first, same reasoning as
  /// [KehaiTray._setAutostart] — the checkbox never lies about what's saved
  /// even if the rest of this fails.
  Future<void> setOledCareEnabled(bool enabled) async {
    await _prefs?.setOledCareEnabled(enabled);
    if (!enabled) {
      oledCare.stop(snapBack: true);
      return;
    }
    if (!isSupported || !windowMode.isMini) return;
    try {
      final base =
          _prefs?.miniWindowPosition ?? (await windowManager.getBounds()).topLeft;
      oledCare.start(base);
    } catch (error) {
      debugPrint('oled care did not start: $error');
    }
  }

  /// window_manager has no "clear the maximum" call, so hand it something
  /// bigger than any display the user is plausibly sitting in front of.
  static const Size _noMaximum = Size(10000, 10000);

  /// The usable desktop rectangle (screen minus panels/taskbar), derived
  /// from where window_manager would place a window of [probe] at two
  /// opposite corners. Falls back to "effectively unbounded", which makes
  /// [anchorResize] skip clamping rather than guess wrong.
  Future<Rect> _workArea(Size probe) async {
    try {
      final topLeft = await calcWindowPosition(probe, Alignment.topLeft);
      final bottomRight = await calcWindowPosition(
        probe,
        Alignment.bottomRight,
      );
      return Rect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        bottomRight.dx + probe.width,
        bottomRight.dy + probe.height,
      );
    } catch (error) {
      debugPrint('work area unknown ($error) — placing without clamping');
      return const Rect.fromLTWH(-100000, -100000, 200000, 200000);
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
  void onWindowMoved() {
    // This move was one of oledCare's own — either a nudge or its
    // snap-back-to-base on disable — not a user drag: consume the flag and
    // skip scheduling a persist, or the wandering/snapped position would
    // get written back as the new base and the card would (slowly) walk
    // away from wherever the user actually put it.
    if (_oledCareNudging) {
      _oledCareNudging = false;
      _nudgeGuardTimer?.cancel();
      return;
    }
    _schedulePersist();
  }

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
      final bounds = await windowManager.getBounds();
      // The card and the panel remember their own spots: dragging the little
      // window to a corner shouldn't move the panel there too.
      if (windowMode.isMini) {
        await prefs.setMiniWindowPosition(bounds.topLeft);
        // Reached only for a real user drag (see onWindowMoved) — this is
        // the "hook the existing drag-end/position-save path" [OledCare]
        // needs: the drop becomes the new base for every nudge from here.
        oledCare.onUserMoved(bounds.topLeft);
      } else {
        await prefs.setWindowBounds(bounds);
      }
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
