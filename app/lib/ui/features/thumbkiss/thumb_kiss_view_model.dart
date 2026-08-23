import 'dart:async';
import 'dart:ui' show Offset;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/touch_repository.dart';
import '../../../domain/models/touch_point.dart';
import 'thumb_kiss_logic.dart';

/// Drives the thumb-kiss touch area: throttled posting of my own fingertip
/// while I press, realtime tracking of the partner's, and the "met" edge
/// that triggers the celebration moment (sparkle + haptic — wired by
/// [ThumbKissWindow], not here, since [HapticFeedback] and animation are
/// widget-layer concerns).
///
/// Self-contained under `ui/features/thumbkiss`, same as `InstantsWindow`'s
/// batch — this builds the feature but does not wire it into the home
/// tray/layout; a caller just needs a [ThumbKissViewModel] wired to real
/// repositories.
class ThumbKissViewModel extends ChangeNotifier {
  ThumbKissViewModel({
    required AuthRepository authRepository,
    required TouchRepository touchRepository,
    this.onMet,
  }) : _authRepository = authRepository,
       _touchRepository = touchRepository;

  final AuthRepository _authRepository;
  final TouchRepository _touchRepository;

  /// Called once on the false→true "met" edge — the widget layer turns
  /// this into `HapticFeedback.mediumImpact()`. Never called again while
  /// still met (no haptic spam while two thumbs sit still together);
  /// fires again only after a fresh not-met→met transition.
  final void Function()? onMet;

  /// My current fingertip, normalized 0..1 — null while not pressing.
  Offset? myTouch;
  DateTime? _myTouchAt;

  /// The partner's most recently received touch point, whether or not
  /// it's still fresh — see [partnerVisible] for the freshness-gated view.
  TouchPoint? partnerTouch;

  bool isMet = false;

  Timer? _ticker;
  UnsubscribeFunc? _unsub;
  DateTime? _lastSentAt;

  String? get _coupleId => _authRepository.coupleId;
  String get _myId => _authRepository.currentUserId;

  /// The partner's fingertip, gated by freshness — null once it's aged
  /// past [touchFreshWindow], even if [partnerTouch] itself is still set
  /// (kept around so a fresh point arriving right after doesn't need to
  /// reallocate).
  bool get partnerVisible {
    final touch = partnerTouch;
    return touch != null && isTouchFresh(touch.at, clock.now());
  }

  Future<void> init() async {
    _unsub = await _touchRepository.subscribe((touch) {
      if (touch.userId == _myId) return; // ignore my own echo, if any
      partnerTouch = touch;
      _reevaluate();
    });
    // Freshness (mine and the partner's) decays with time alone, not just
    // on new events — a periodic re-check is what fades a lifted thumb's
    // glow and drops a stale "met" state even when nothing new arrives.
    //
    // The tick also keeps a HELD-STILL press alive: pointer events only fire
    // on movement, so without this a resting thumb would stop posting, go
    // stale on the partner's screen after touchFreshWindow, and flicker back
    // only on micro-movements (shipped bug) — and my own freshness would
    // decay mid-press, breaking met-detection for two thumbs at rest. While
    // [myTouch] is set the press itself is the liveness signal: restamp it
    // and re-send at the throttle's own pace (~4/s).
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final mine = myTouch;
      if (mine != null) {
        _myTouchAt = clock.now();
        _maybeSend(mine);
      }
      _reevaluate();
    });
  }

  /// Called by the touch area on every pointer-down/move while a press is
  /// active. [normalized] must already be clamped to 0..1 by the caller
  /// (the widget knows the touch area's actual size; this layer doesn't).
  void onTouchMove(Offset normalized) {
    myTouch = normalized;
    _myTouchAt = clock.now();
    _maybeSend(normalized);
    _reevaluate();
  }

  /// Called on pointer-up/cancel. Deliberately does not post anything —
  /// the partner just sees my last point age out of [touchFreshWindow] on
  /// its own, which is simpler than adding a "lifted" signal and reads the
  /// same to them either way.
  void onTouchEnd() {
    myTouch = null;
    _myTouchAt = null;
    _reevaluate();
  }

  void _maybeSend(Offset point) {
    final now = clock.now();
    if (!shouldSendTouch(lastSentAt: _lastSentAt, now: now)) return;
    final coupleId = _coupleId;
    if (coupleId == null) return;
    _lastSentAt = now;
    unawaited(
      _touchRepository
          .send(coupleId: coupleId, userId: _myId, x: point.dx, y: point.dy)
          .catchError((_) {
            // Best-effort — the next throttled tick (still ~250ms away)
            // retries; a dropped point or two just reads as a beat of lag.
          }),
    );
  }

  void _reevaluate() {
    final now = clock.now();
    final theirs = partnerTouch;
    final met = didMeet(
      mine: myTouch,
      mineAt: _myTouchAt,
      theirs: theirs?.offset,
      theirsAt: theirs?.at,
      now: now,
    );
    final becameMet = met && !isMet;
    isMet = met;
    notifyListeners();
    if (becameMet) onMet?.call();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _unsub?.call();
    super.dispose();
  }
}
