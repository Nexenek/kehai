import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;
import 'package:pocketbase/pocketbase.dart';

import '../../../domain/models/portal_signal.dart';
import '../../../ui/core/strings/app_strings.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/portal_signal_repository.dart';
import '../../repositories/turn_repository.dart';
import 'portal_log.dart';
import 'portal_media.dart';

/// Where a portal call is, from this device's point of view.
///
/// ```
///                 knock()                    they accept
///   idle ───────────────────────► knocking ──────────────► connecting
///     ▲            their knock                accept()          │
///     ├───────────────────────────► knocked ──────────┘         │
///     │                                │ decline()              │ media up
///     │                                ▼                        ▼
///     └──────────────── closing ◄──── hangUp() / hangup / error / connected
/// ```
///
/// [closing] is brief and always ends in [idle]; it exists so the UI can
/// tell "putting the camera away" apart from "nothing is happening", and so
/// nothing can start a second call while the first is still letting go of
/// the hardware.
///
/// A connected call that loses ICE goes back to [connecting] for the length
/// of one automatic restart (see [PortalEngine.isReconnecting]), rather than
/// sitting in [connected] over a frozen picture. That is deliberate and the
/// curtain depends on it: `PortalCallScreen` parts the drapes on
/// `state == connected` and nothing else, so a restart closes them on its
/// own — the window is only ever *shown* open while media is actually
/// flowing. Any surface built on this enum inherits that honesty for free;
/// none of them should special-case reconnection to keep the drapes open.
enum PortalState { idle, knocking, knocked, connecting, connected, closing }

/// Who sends the offer. Deterministic and symmetric: whoever's user id
/// sorts first does the offering, no matter who knocked.
///
/// This is the whole answer to glare. Tying the role to "who knocked"
/// breaks the moment both people knock in the same second (each thinks it
/// is the caller, both send offers, both peer connections choke on an offer
/// while in have-local-offer). Tying it to a value both sides already agree
/// on — the ids, which the server stamps on every signal and neither client
/// can forge — means both peers compute the same answer without a single
/// extra round trip.
bool portalShouldOffer({required String me, required String partner}) =>
    me.compareTo(partner) < 0;

/// How long a knock stands before it gives up, on both sides: the knocker
/// stops waiting, and an unanswered knock stops offering to be answered.
const portalKnockTimeout = Duration(seconds: 45);

/// How long an in-flight ICE restart gets to reach `connected` again before
/// the call is declared lost.
///
/// Fifteen seconds is roughly two full gathering-and-checking cycles on a
/// LAN, and comfortably longer than the pause while a phone hands its
/// route from wifi to cellular. Longer than this and the curtain is just
/// lying to somebody who has already noticed the picture froze.
const portalIceRestartTimeout = Duration(seconds: 15);

/// How old a knock or accept may be and still mean something.
///
/// The collection is purged hourly, and a realtime subscription that
/// reconnects can redeliver — so without this, a knock from twenty minutes
/// ago could open a camera. Sixty seconds is deliberately much looser than
/// the couple of seconds a handshake needs: this compares a *server*
/// timestamp against the *local* clock, and those drift (the thumb-kiss
/// freshness bug was exactly that comparison with a three-second window).
/// Loose enough to survive drift, tight enough that nothing stale opens a
/// curtain.
const portalSignalFreshWindow = Duration(seconds: 60);

/// Is this signal recent enough to act on? A timestamp from the future
/// (clock skew the other way) counts as fresh — the only thing being
/// guarded against here is *staleness*.
bool isPortalSignalFresh(DateTime created, DateTime now) =>
    now.difference(created) < portalSignalFreshWindow;

// User-visible copy for [PortalEngine.lastError] — this IS the curtain's
// voice, per the note above. `portalNoAnswer` and `portalErrorGeneric` are
// the two app_strings.dart ships for portal mode; the timeout case is
// specific enough to earn its own real string, and everything else that can
// go wrong (signal failed, camera/mic refused, the peer connection died)
// reads the same to the person looking at the curtain — "it couldn't open,
// try again" — so they all collapse onto the one generic error rather than
// multiplying variants nobody would tell apart. Being told "not right now"
// after a decline is a different feeling from an error, so it keeps its own
// small, gentle line instead.
const _errNoAnswer = AppStrings.portalNoAnswer;
const _errDeclined = 'not right now (´･_･`)';
const _errSignalFailed = AppStrings.portalErrorGeneric;
const _errMediaFailed = AppStrings.portalErrorGeneric;
const _errLostPartner = AppStrings.portalErrorGeneric;

/// The slice of [PortalEngine] the call screen reads. The screen talks to
/// this rather than to the engine directly so a widget test can render
/// every state against a fake — see the seam note on [PortalMedia]: the
/// engine itself is testable, but a *screen* test shouldn't have to build
/// repositories at all.
abstract class PortalCallSurface implements Listenable {
  PortalState get state;
  String? get lastError;
  RTCVideoRenderer? get localRenderer;
  RTCVideoRenderer? get remoteRenderer;

  /// The partner's user id, once a signal (their knock, or their accept of
  /// mine) has told us who they are — null before that. The curtain
  /// doesn't need this to render, but [PortalKnockBridge] does, for the
  /// notification a knock raises.
  String? get partnerId;
  Future<void> knock();
  Future<void> accept();
  Future<void> decline();
  Future<void> hangUp();
}

/// Portal mode's transport layer: the state machine that turns knocks and
/// SDPs into a live window between two homes (kb/decisions.md ADR-9 — raw
/// WebRTC P2P for exactly two peers, no SFU).
///
/// Two rules shape everything in here.
///
/// **The camera opens only after both people have consented.** Not on
/// knock, not on "probably about to accept", not to warm the encoder up.
/// One method in [PortalMedia] touches capture hardware and it is called
/// from exactly one place ([_beginConnect]), which is only reachable once a
/// knock and an accept both exist.
///
/// **The camera is released on every path out.** Hang up, remote hang up,
/// declined, timed out, ICE failed, getUserMedia threw, engine disposed,
/// user logged out — all of them funnel through [_teardown], and every
/// teardown closes the media before anything that could fail or block.
class PortalEngine extends ChangeNotifier implements PortalCallSurface {
  PortalEngine({
    required AuthRepository auth,
    required PortalSignalRepository signals,
    required TurnRepository turn,
    PortalMedia Function()? createMedia,
    Duration knockTimeout = portalKnockTimeout,
    Duration iceRestartTimeout = portalIceRestartTimeout,
  }) : _auth = auth,
       _signals = signals,
       _turn = turn,
       _createMedia = createMedia ?? WebRtcPortalMedia.new,
       _knockTimeout = knockTimeout,
       _iceRestartTimeout = iceRestartTimeout;

  final AuthRepository _auth;
  final PortalSignalRepository _signals;
  final TurnRepository _turn;
  final PortalMedia Function() _createMedia;
  final Duration _knockTimeout;
  final Duration _iceRestartTimeout;

  PortalState _state = PortalState.idle;
  String? _lastError;
  PortalMedia? _media;
  UnsubscribeFunc? _unsub;
  Timer? _knockTimer;
  bool _disposed = false;

  /// Learned from the first signal the partner sends (their knock, or their
  /// accept of mine) rather than looked up: the server stamps `from` itself
  /// and refuses to let anyone forge it, so a signal is the most
  /// trustworthy source of the partner's id there is — and by the time the
  /// role decision matters, at least one has always arrived.
  String? _partnerId;

  bool _offerer = false;

  /// Candidates that landed before the remote description did. Classic
  /// trickle-ICE race: the peer starts gathering the instant it has a local
  /// description, so its first candidates routinely overtake its own SDP on
  /// the wire. `addCandidate` before `setRemoteDescription` throws, so they
  /// wait here — in arrival order, which is roughly priority order — and
  /// get flushed the moment the description lands.
  final List<Map<String, dynamic>> _pendingCandidates = [];
  bool _remoteReady = false;

  /// Exactly one ICE restart per call. A second failure after a restart has
  /// already been tried is not a blip, it's a route that doesn't exist —
  /// and a loop of restarts would hold the camera open indefinitely on a
  /// call that is never going to work.
  bool _restartAttempted = false;

  /// A restart is in the air: either we sent the restart offer, or we saw
  /// the failure and are waiting for theirs. Drives the honest-curtain rule
  /// (see [isReconnecting]).
  bool _restarting = false;
  Timer? _restartTimer;

  /// Serializes everything that mutates the machine. Signals arrive from a
  /// realtime callback while the UI is calling methods and the peer
  /// connection is firing state changes; without one queue, an `ice` signal
  /// could be handled halfway through the `offer` that makes it legal.
  Future<void> _tail = Future<void>.value();

  @override
  PortalState get state => _state;

  @override
  String? get lastError => _lastError;

  @override
  RTCVideoRenderer? get localRenderer => _media?.localRenderer;

  @override
  RTCVideoRenderer? get remoteRenderer => _media?.remoteRenderer;

  @override
  String? get partnerId => _partnerId;

  /// Which side of the SDP dance this device is on, once decided. Exposed
  /// for the debug surface — nothing about the call depends on the user
  /// knowing.
  bool get isOfferer => _offerer;

  /// True while a connected call is being re-established after an ICE
  /// failure. The state goes back to [PortalState.connecting] for the
  /// duration — the curtain half-closes rather than pretending a frozen
  /// picture is a live one — and this flag is only for a surface that wants
  /// to word it as "reconnecting" rather than "opening".
  bool get isReconnecting => _restarting;

  String get _myId => _auth.currentUserId;

  /// Starts listening for the partner's signals — the engine is useless
  /// before it (a knock would go out with nobody listening for the reply).
  /// Idempotent, so the debug entry point can call it on every open without
  /// stacking subscriptions.
  Future<void> init() async {
    if (_unsub != null || _disposed) return;
    _unsub = await _signals.subscribe(_onSignal, onOwnSignal: _onOwnSignal);
  }

  // ---------------------------------------------------------------- intent

  @override
  Future<void> knock() => _act(() async {
    if (_state != PortalState.idle) return;
    _lastError = null;
    _setState(PortalState.knocking);
    _armKnockTimer();
    try {
      await _signals.create(PortalSignalKind.knock);
    } catch (_) {
      await _teardown(sendHangup: false, error: _errSignalFailed);
    }
  });

  @override
  Future<void> accept() => _act(() async {
    if (_state != PortalState.knocked) return;
    _cancelKnockTimer();
    try {
      await _signals.create(PortalSignalKind.accept);
    } catch (_) {
      await _teardown(sendHangup: false, error: _errSignalFailed);
      return;
    }
    await _beginConnect();
  });

  @override
  Future<void> decline() => _act(() async {
    if (_state != PortalState.knocked) return;
    _cancelKnockTimer();
    _partnerId = null;
    _setState(PortalState.idle);
    try {
      await _signals.create(PortalSignalKind.decline);
    } catch (_) {
      // Nothing to salvage: we're already not answering. Their knock times
      // out on its own in [portalKnockTimeout].
    }
  });

  @override
  Future<void> hangUp() => _act(() async {
    if (_state == PortalState.idle) return;
    await _teardown(sendHangup: true, error: null);
  });

  // --------------------------------------------------------------- signals

  void _onSignal(PortalSignal signal) {
    // The repository already dropped my own echo, so anything arriving here
    // is the partner's.
    unawaited(_act(() => _handle(signal)));
  }

  Future<void> _handle(PortalSignal signal) async {
    final now = clock.now();
    switch (signal.kind) {
      case PortalSignalKind.knock:
        if (!isPortalSignalFresh(signal.created, now)) return;
        if (_state == PortalState.idle) {
          _partnerId = signal.fromId;
          _lastError = null;
          _setState(PortalState.knocked);
          _armKnockTimer();
          return;
        }
        // Both of us knocked at once. Two knocks are two consents — there's
        // nothing left to ask — so answer it and start. They'll do the same
        // with ours, and [portalShouldOffer] keeps the two starts from
        // colliding.
        if (_state == PortalState.knocking) {
          _partnerId = signal.fromId;
          _cancelKnockTimer();
          try {
            await _signals.create(PortalSignalKind.accept);
          } catch (_) {
            await _teardown(sendHangup: false, error: _errSignalFailed);
            return;
          }
          await _beginConnect();
        }

      case PortalSignalKind.accept:
        if (!isPortalSignalFresh(signal.created, now)) return;
        if (_state != PortalState.knocking) return;
        // [_beginConnect] cancels this too, but disarming it at the moment
        // the knock is actually answered keeps the timer's lifetime tied to
        // the state it guards rather than to a callee's housekeeping.
        _cancelKnockTimer();
        _partnerId = signal.fromId;
        await _beginConnect();

      case PortalSignalKind.decline:
        if (_state != PortalState.knocking) return;
        _cancelKnockTimer();
        _partnerId = null;
        _lastError = _errDeclined;
        _setState(PortalState.idle);

      case PortalSignalKind.offer:
        // Only the answering side ever takes an offer. It arrives twice in
        // a call's life at most: once to open it, and once more if ICE
        // failed and the offerer is restarting — which is why `connected`
        // is accepted here as well as `connecting`. Anywhere else it's a
        // stale record or a confused peer.
        if (_offerer) return;
        if (_state != PortalState.connecting &&
            _state != PortalState.connected) {
          return;
        }
        final media = _media;
        if (media == null) return;
        // A second offer, after we already have a remote description, can
        // only be a renegotiation — the ICE restart. Half-close the curtain
        // and give it the same window the offering side gave itself.
        if (_remoteReady) {
          portalLog('restart offer arrived — reconnecting');
          _restartAttempted = true;
          _beginRestartWindow();
        }
        try {
          await media.acceptRemoteDescription(signal.payload);
          await _flushCandidates(media);
          final answer = await media.createAnswer();
          if (_media != media) return;
          await _signals.create(PortalSignalKind.answer, payload: answer);
        } catch (_) {
          await _teardown(sendHangup: true, error: _errMediaFailed);
        }

      case PortalSignalKind.answer:
        // Same widening as `offer`, for the other side of a restart: the
        // answer to a restart offer can land while we still read as
        // connected.
        if (!_offerer) return;
        if (_state != PortalState.connecting &&
            _state != PortalState.connected) {
          return;
        }
        final media = _media;
        if (media == null) return;
        try {
          await media.acceptRemoteDescription(signal.payload);
          await _flushCandidates(media);
        } catch (_) {
          await _teardown(sendHangup: true, error: _errMediaFailed);
        }

      case PortalSignalKind.ice:
        final media = _media;
        if (media == null) return;
        if (!_remoteReady) {
          _pendingCandidates.add(signal.payload);
          return;
        }
        try {
          await media.addRemoteCandidate(signal.payload);
        } catch (_) {
          // One rejected candidate is not a failed call — ICE tries every
          // other pair it has. Dropping it silently is the correct
          // behaviour here.
        }

      case PortalSignalKind.hangup:
        if (_state == PortalState.idle) return;
        // No echo: they already know. Sending one back would race their
        // next knock.
        await _teardown(sendHangup: false, error: null);
    }
  }

  /// A signal from ME, but from a *different* device — the repository
  /// drops these by default (see [PortalSignalRepository.subscribe]'s note
  /// on why), but the engine asks to hear them anyway for exactly this
  /// case: two of my own devices both saw the partner's knock and both sat
  /// down in [PortalState.knocked], and I answered on the other one. This
  /// device has to find out, or it sits there forever showing "someone's at
  /// the window" for a knock that's already been let in — or worse, tries
  /// to accept it too.
  ///
  /// Only matters while genuinely waiting on a decision: outside
  /// [PortalState.knocked] there's nothing to lapse, and every other own
  /// signal (my own knock, my own offer/answer/ice echoing back) is just
  /// noise this device already knows about first-hand.
  void _onOwnSignal(PortalSignal signal) {
    unawaited(_act(() => _handleOwnSignal(signal)));
  }

  Future<void> _handleOwnSignal(PortalSignal signal) async {
    if (_state != PortalState.knocked) return;
    switch (signal.kind) {
      case PortalSignalKind.accept:
      case PortalSignalKind.decline:
      case PortalSignalKind.hangup:
        // The other device already answered — lapse silently: no media (it
        // was never opened here), no signal echoed back (that device, or
        // the partner, already has the answer they need).
        _cancelKnockTimer();
        _partnerId = null;
        _lastError = null;
        _setState(PortalState.idle);
      case PortalSignalKind.knock:
      case PortalSignalKind.offer:
      case PortalSignalKind.answer:
      case PortalSignalKind.ice:
        return;
    }
  }

  Future<void> _flushCandidates(PortalMedia media) async {
    _remoteReady = true;
    final buffered = List<Map<String, dynamic>>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in buffered) {
      if (_media != media) return;
      try {
        await media.addRemoteCandidate(candidate);
      } catch (_) {
        // Same as above — a candidate that won't take is just one fewer
        // path to try.
      }
    }
  }

  // ----------------------------------------------------------------- media

  /// Both consents exist. This — and only this — is where the camera opens.
  Future<void> _beginConnect() async {
    _cancelKnockTimer();
    final partnerId = _partnerId;
    if (partnerId == null) {
      await _teardown(sendHangup: true, error: _errLostPartner);
      return;
    }
    _lastError = null;
    _offerer = portalShouldOffer(me: _myId, partner: partnerId);
    _remoteReady = false;
    _restartAttempted = false;
    _restarting = false;
    _pendingCandidates.clear();
    portalLog('both consented — role: ${_offerer ? 'offerer' : 'answerer'}');
    _setState(PortalState.connecting);

    final media = _createMedia();
    _media = media;
    media.onLocalCandidate = (candidate) => unawaited(
      _act(() async {
        if (_media != media) return;
        try {
          await _signals.create(PortalSignalKind.ice, payload: candidate);
        } catch (_) {
          // A dropped candidate costs one candidate pair, not the call.
        }
      }),
    );
    // Serves the first connect and a successful restart alike — either way
    // the picture is live again and the restart window can be stood down.
    media.onConnected = () => unawaited(
      _act(() async {
        if (_media != media || _state != PortalState.connecting) return;
        _cancelRestartTimer();
        _restarting = false;
        _setState(PortalState.connected);
      }),
    );
    media.onFailed = () => unawaited(
      _act(() async {
        if (_media != media) return;
        await _handleIceFailure(media);
      }),
    );
    media.onLost = (reason) => unawaited(
      _act(() async {
        if (_media != media) return;
        await _teardown(sendHangup: true, error: _errLostPartner);
      }),
    );

    try {
      // Never fatal: no TURN configured answers an empty list, and an
      // unreachable endpoint answers the same. Host candidates carry a
      // tailnet on their own (see [TurnRepository]'s no-public-STUN note).
      final iceServers = await _turn.fetchIceServers();
      if (_media != media) return;

      await media.open(iceServers);
      // Somebody hung up while getUserMedia was in flight. The teardown
      // that did it closed this object *before* it had a camera, so the
      // close it ran was a no-op on hardware that has since been handed
      // over — close it again. [PortalMedia.close] is idempotent precisely
      // for this window.
      if (_media != media) {
        await media.close();
        await media.dispose();
        return;
      }
      // A renderer now exists, so the screen has something to show — the
      // state hasn't changed, but what it can draw has.
      _notify();

      if (_offerer) {
        final offer = await media.createOffer();
        if (_media != media) return;
        await _signals.create(PortalSignalKind.offer, payload: offer);
      }
      // The answering side does nothing here — it waits for their offer,
      // which the `offer` branch above picks up.
    } catch (_) {
      await _teardown(sendHangup: true, error: _errMediaFailed);
    }
  }

  // ----------------------------------------------------------- ice restart

  /// ICE gave up. Try once to save the call before dropping the curtain.
  ///
  /// A `failed` peer connection is not the same as a lost peer. It's what
  /// the ICE agent says when every pair it had stopped working — which is
  /// the normal shape of a route change: a phone swapping wifi for
  /// cellular, or (the case this was written for) two devices on the same
  /// wifi whose candidates were gathered over a tailnet route that then
  /// went away. Re-gathering from scratch usually finds the pair that was
  /// there all along.
  ///
  /// Only the offerer restarts — the same lexicographic rule that decides
  /// the first offer decides this one, so the two sides can't both
  /// renegotiate at once. The answering side does the mirror of it: half
  /// close the curtain and wait for the restart offer within the same
  /// window.
  Future<void> _handleIceFailure(PortalMedia media) async {
    if (_state != PortalState.connected && _state != PortalState.connecting) {
      return;
    }
    if (_restartAttempted) {
      portalLog('ice failed again after a restart — giving up');
      await _teardown(sendHangup: true, error: _errLostPartner);
      return;
    }
    _restartAttempted = true;
    _beginRestartWindow();

    if (!_offerer) {
      portalLog('ice failed — waiting for their restart offer');
      return;
    }
    try {
      portalLog('ice failed — restarting as the offering side');
      await media.restartIce();
      final offer = await media.createOffer(iceRestart: true);
      if (_media != media) return;
      await _signals.create(PortalSignalKind.offer, payload: offer);
    } catch (_) {
      await _teardown(sendHangup: true, error: _errLostPartner);
    }
  }

  /// Half-closes the curtain and starts the clock. Both sides of a restart
  /// run this — the one that noticed the failure, and the one that only
  /// finds out when the restart offer arrives.
  void _beginRestartWindow() {
    _restarting = true;
    _setState(PortalState.connecting);
    _notify(); // the state may already have been `connecting`
    _cancelRestartTimer();
    _restartTimer = Timer(_iceRestartTimeout, () {
      unawaited(
        _act(() async {
          if (!_restarting) return;
          portalLog('restart window elapsed with no connection — giving up');
          await _teardown(sendHangup: true, error: _errLostPartner);
        }),
      );
    });
  }

  void _cancelRestartTimer() {
    _restartTimer?.cancel();
    _restartTimer = null;
  }

  // -------------------------------------------------------------- teardown

  /// The one way out. Media closes before the hang-up signal is awaited:
  /// a slow or dead network must never be what keeps a camera on.
  Future<void> _teardown({required bool sendHangup, String? error}) async {
    if (_state == PortalState.idle && _media == null) {
      if (error != null) {
        _lastError = error;
        _notify();
      }
      return;
    }
    _cancelKnockTimer();
    _cancelRestartTimer();
    _restarting = false;
    _restartAttempted = false;
    if (error != null) {
      _lastError = error;
      portalLog('tearing down: $error');
    }
    _setState(PortalState.closing);

    // Kick the signal off first so the partner's curtain starts falling at
    // the same moment as ours, but never wait on it before releasing the
    // hardware.
    Future<void>? hangup;
    if (sendHangup) {
      hangup = _signals.create(PortalSignalKind.hangup).catchError((Object _) {
        // Best effort. If it doesn't land, their side times out or notices
        // the connection drop.
      });
    }

    final media = _media;
    _media = null;
    _pendingCandidates.clear();
    _remoteReady = false;
    _partnerId = null;
    _offerer = false;
    if (media != null) {
      media.onLocalCandidate = null;
      media.onConnected = null;
      media.onFailed = null;
      media.onLost = null;
      await media.close();
      await media.dispose();
    }

    if (hangup != null) await hangup;
    _setState(PortalState.idle);
  }

  void _armKnockTimer() {
    _cancelKnockTimer();
    _knockTimer = Timer(_knockTimeout, () {
      unawaited(
        _act(() async {
          final wasKnocking = _state == PortalState.knocking;
          if (!wasKnocking && _state != PortalState.knocked) return;
          await _teardown(
            // Only the knocker owes the other side a hang-up; an unanswered
            // incoming knock just lapses, and saying "nobody came" to the
            // person who didn't answer would be nonsense.
            sendHangup: wasKnocking,
            error: wasKnocking ? _errNoAnswer : null,
          );
        }),
      );
    });
  }

  void _cancelKnockTimer() {
    _knockTimer?.cancel();
    _knockTimer = null;
  }

  /// Queues [action] behind everything already in flight. Actions never
  /// throw (each handles its own failure into [_teardown]), so the chain
  /// can't be poisoned.
  Future<void> _act(Future<void> Function() action) {
    final next = _tail.then((_) async {
      if (_disposed) return;
      await action();
    });
    _tail = next;
    return next;
  }

  void _setState(PortalState next) {
    if (_state == next) return;
    // Always logged, release included: five or six lines per call, no
    // addresses, and the first thing worth seeing when a call misbehaves.
    portalLog('${_state.name} → ${next.name}');
    _state = next;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Ends the engine. [ChangeNotifier.dispose] is synchronous, so the
  /// asynchronous half of letting go can't be awaited here — but it is
  /// *started* here, in the right order: the media object is detached and
  /// closed immediately, before anything that could block. The camera is
  /// released whether or not anyone waits for this to finish.
  @override
  void dispose() {
    _disposed = true;
    _cancelKnockTimer();
    _cancelRestartTimer();
    _unsub?.call();
    _unsub = null;

    final media = _media;
    _media = null;
    _pendingCandidates.clear();
    if (media != null) {
      media.onLocalCandidate = null;
      media.onConnected = null;
      media.onFailed = null;
      media.onLost = null;
      // Tell them the window shut, then let go of the hardware. Neither is
      // awaited; both are already under way when this returns.
      if (_state != PortalState.idle) {
        unawaited(
          _signals
              .create(PortalSignalKind.hangup)
              .catchError((Object _) {}),
        );
      }
      unawaited(media.dispose());
    }
    _state = PortalState.idle;
    super.dispose();
  }
}
