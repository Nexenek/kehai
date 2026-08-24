import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// OLED burn-in protection for the always-there mini card
/// (kb/platform-desktop.md): sitting still hour after hour, a static
/// pastel rectangle is exactly the shape OLED burn-in loves. Two
/// independent countermeasures, both gated on the same "oled care" tray
/// checkbox ([PrefsService.oledCareEnabled] — off by default) and both only
/// active while the window is actually the mini card:
///
///  - a slow random walk that keeps the card within [nudgeRange] pixels of
///    its BASE position on both axes — never persisted as a new base, only
///    a real user drop does that (via [onUserMoved]) — so no single pixel
///    sits under the same edge for a whole session, and the card can never
///    drift away from where it was put;
///  - idle dimming: down to [dimmedOpacity] after [idleDimDelay] with no
///    pointer over the card, undimming the instant it comes back. Roughly
///    half-brightness pixels wear at roughly half the rate — the bigger win
///    of the two.
///
/// Pure scheduling/math, no window_manager import: the caller hands in
/// [moveTo] and [setOpacity] — the only two things this ever asks the real
/// window to do — which is what makes it testable with `fakeAsync` and no
/// window at all (see oled_care_test.dart). Timer-driven throughout, never
/// `DateTime.now()`, so `fakeAsync` drives every bit of it deterministically
/// — including [random], which a test can seed or replace outright.
class OledCare {
  OledCare({
    required Future<void> Function(Offset position) moveTo,
    required Future<void> Function(double opacity) setOpacity,
    math.Random? random,
  }) : _moveTo = moveTo,
       _setOpacity = setOpacity,
       _random = random ?? math.Random();

  /// How often the card takes a small step. Slow enough that you'd have to
  /// be staring right at it to ever catch one happening.
  static const nudgeInterval = Duration(seconds: 60);

  /// Both axes, independently: every nudge lands somewhere in
  /// `base.dx ± nudgeRange, base.dy ± nudgeRange`, never further — and
  /// always measured from [base], never from the previous nudge, so the
  /// card wanders without ever compounding away from its spot.
  static const nudgeRange = 24.0;

  /// How long the pointer has to be away before the card dims.
  static const idleDimDelay = Duration(minutes: 2);

  /// Roughly half brightness — the actual OLED-wear win.
  static const dimmedOpacity = 0.55;
  static const fullOpacity = 1.0;

  final Future<void> Function(Offset position) _moveTo;
  final Future<void> Function(double opacity) _setOpacity;
  final math.Random _random;

  Offset? _base;
  bool _active = false;
  bool _hovering = false;
  bool _dimmed = false;

  Timer? _nudgeTimer;
  Timer? _idleTimer;

  /// True while the nudge/dim machinery is actually scheduled — i.e. the
  /// checkbox is on AND the window is the mini card right now.
  bool get isActive => _active;

  /// True once idle dimming has actually lowered the opacity.
  bool get isDimmed => _dimmed;

  /// The position every nudge is measured from: the user's last drop, or
  /// wherever [start] was told the card already sat.
  Offset? get base => _base;

  /// The window just became the mini card (or the checkbox was just
  /// switched on while already mini): start nudging around [base] and start
  /// the idle-dim countdown as though the pointer just left.
  void start(Offset base) {
    _base = base;
    _active = true;
    _hovering = false;
    _restartNudgeTimer();
    _restartIdleTimer();
  }

  /// The window stopped being the mini card — checkbox turned off, or it
  /// expanded to the full panel: no more scheduling, and always back to
  /// full brightness (a dimmed panel would make no sense either way).
  /// [snapBack] additionally asks the card to return to [base] itself —
  /// used for "checkbox off" (stop + snap back to base); left false for
  /// "just expanded", since growing into the panel moves the window anyway.
  void stop({bool snapBack = false}) {
    _active = false;
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_dimmed) {
      _dimmed = false;
      unawaited(_setOpacity(fullOpacity));
    }
    final base = _base;
    if (snapBack && base != null) {
      unawaited(_moveTo(base));
    }
  }

  /// The user dropped the window themselves: from now on nudges measure
  /// from this new spot. Callers must route only real drag-end positions
  /// here — never one of [moveTo]'s own nudge calls, or the walk would
  /// start chasing itself.
  void onUserMoved(Offset newBase) {
    _base = newBase;
    if (_active) _restartNudgeTimer();
  }

  /// The pointer arrived over the card: undim immediately (if dimmed) and
  /// hold off the idle countdown while it stays.
  void onHoverEnter() {
    _hovering = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_dimmed) {
      _dimmed = false;
      unawaited(_setOpacity(fullOpacity));
    }
  }

  /// The pointer left: start counting back down toward a dim.
  void onHoverExit() {
    _hovering = false;
    if (_active) _restartIdleTimer();
  }

  void _restartNudgeTimer() {
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer.periodic(nudgeInterval, (_) => _nudge());
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDimDelay, () {
      _idleTimer = null;
      if (!_active || _hovering) return;
      _dimmed = true;
      unawaited(_setOpacity(dimmedOpacity));
    });
  }

  void _nudge() {
    final base = _base;
    if (base == null || !_active) return;
    final dx = (_random.nextDouble() * 2 - 1) * nudgeRange;
    final dy = (_random.nextDouble() * 2 - 1) * nudgeRange;
    unawaited(_moveTo(Offset(base.dx + dx, base.dy + dy)));
  }

  /// Called from the owning service's teardown — cancels everything without
  /// touching the window; there's nothing left to move it back on.
  void dispose() {
    _nudgeTimer?.cancel();
    _idleTimer?.cancel();
  }
}
