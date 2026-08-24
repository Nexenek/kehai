import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/portal_signal_repository.dart';
import 'package:couples_app/data/repositories/turn_repository.dart';
import 'package:couples_app/data/services/portal/portal_engine.dart';
import 'package:couples_app/data/services/portal/portal_media.dart';
import 'package:couples_app/domain/models/portal_signal.dart';

/// Records what the engine sent and lets a test push a signal straight into
/// whatever callback [PortalEngine.init] registered — same shape as
/// `_FakePingRepository` in ping_view_model_test.dart.
class _FakeSignals extends PortalSignalRepository {
  _FakeSignals() : super(PocketBase('https://example.invalid'));

  final sent = <PortalSignalKind>[];
  final payloads = <Map<String, dynamic>>[];
  bool failCreate = false;
  int unsubscribed = 0;
  void Function(PortalSignal signal)? _onSignal;
  void Function(PortalSignal signal)? _onOwnSignal;

  bool get isSubscribed => _onSignal != null;

  @override
  Future<void> create(
    PortalSignalKind kind, {
    Map<String, dynamic> payload = const {},
  }) async {
    if (failCreate) throw StateError('no server');
    sent.add(kind);
    payloads.add(payload);
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    void Function(PortalSignal signal) onSignal, {
    void Function(PortalSignal signal)? onOwnSignal,
  }) async {
    _onSignal = onSignal;
    _onOwnSignal = onOwnSignal;
    return () async => unsubscribed++;
  }

  void emit(PortalSignal signal) => _onSignal?.call(signal);

  /// Stands in for the real repository's own-account echo — a signal from
  /// a *different device* logged in as the same user (see
  /// `PortalEngine`'s multi-device guard).
  void emitOwn(PortalSignal signal) => _onOwnSignal?.call(signal);
}

class _FakeTurn extends TurnRepository {
  _FakeTurn() : super(PocketBase('https://example.invalid'));

  IceServers answer = const [];
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    calls++;
    return answer;
  }
}

/// The seam's test double. Nothing native, everything observable — in
/// particular [closed]/[disposed], which is how every teardown assertion in
/// here checks the camera was actually let go of.
class _FakeMedia extends PortalMedia {
  final calls = <String>[];
  final remoteCandidates = <Map<String, dynamic>>[];

  bool opened = false;
  bool closed = false;
  bool disposed = false;
  Map<String, dynamic>? remoteDescription;
  IceServers? openedWith;
  Object? openThrows;

  /// Stands in for the seconds a real `getUserMedia` spends waiting on a
  /// permission dialog — the window in which a user can change their mind.
  Duration openDelay = Duration.zero;

  @override
  Null get localRenderer => null;

  @override
  Null get remoteRenderer => null;

  @override
  Future<void> open(IceServers iceServers) async {
    calls.add('open');
    openedWith = iceServers;
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    if (openThrows != null) throw openThrows!;
    opened = true;
  }

  int iceRestarts = 0;

  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    calls.add(iceRestart ? 'createRestartOffer' : 'createOffer');
    return {'sdp': iceRestart ? 'RESTART' : 'OFFER', 'type': 'offer'};
  }

  @override
  Future<void> restartIce() async {
    calls.add('restartIce');
    iceRestarts++;
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    calls.add('createAnswer');
    return {'sdp': 'ANSWER', 'type': 'answer'};
  }

  @override
  Future<void> acceptRemoteDescription(
    Map<String, dynamic> description,
  ) async {
    calls.add('remoteDescription');
    remoteDescription = description;
  }

  @override
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    calls.add('candidate');
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
  }
}

AuthRepository _loggedIn(String id) {
  final pb = PocketBase('https://example.invalid');
  pb.authStore.save(
    'tok',
    RecordModel({
      'id': id,
      'collectionId': 'c',
      'collectionName': 'users',
      'couple': 'couple1',
    }),
  );
  return AuthRepository(pb);
}

PortalSignal _signal(
  PortalSignalKind kind, {
  Map<String, dynamic> payload = const {},
  DateTime? created,
  String from = 'partner',
}) => PortalSignal(
  id: 'sig',
  fromId: from,
  kind: kind,
  payload: payload,
  created: created ?? clock.now(),
);

/// Everything in the engine funnels through one serialized queue, so
/// draining the microtask/event queue is enough to settle it.
Future<void> _settle() => pumpEventQueue();

void main() {
  late _FakeSignals signals;
  late _FakeTurn turn;
  late _FakeMedia media;

  /// [me] decides the offerer/answerer role against the fixed partner id
  /// 'partner': 'aaa' offers, 'zzz' answers.
  Future<PortalEngine> build({
    String me = 'aaa',
    Duration knockTimeout = portalKnockTimeout,
    Duration iceRestartTimeout = portalIceRestartTimeout,
  }) async {
    final engine = PortalEngine(
      auth: _loggedIn(me),
      signals: signals,
      turn: turn,
      createMedia: () => media,
      knockTimeout: knockTimeout,
      iceRestartTimeout: iceRestartTimeout,
    );
    await engine.init();
    return engine;
  }

  setUp(() {
    signals = _FakeSignals();
    turn = _FakeTurn();
    media = _FakeMedia();
  });

  group('role decision', () {
    test('the smaller id offers, whoever knocked', () {
      expect(portalShouldOffer(me: 'aaa', partner: 'zzz'), isTrue);
      expect(portalShouldOffer(me: 'zzz', partner: 'aaa'), isFalse);
    });

    test('both peers compute opposite roles from the same pair', () {
      const a = 'k9x2';
      const b = 'k9x30';
      expect(
        portalShouldOffer(me: a, partner: b),
        isNot(portalShouldOffer(me: b, partner: a)),
      );
    });
  });

  group('staleness guard', () {
    test('a signal from a minute ago no longer counts', () {
      final now = DateTime(2026, 8, 24, 12);
      expect(isPortalSignalFresh(now.subtract(const Duration(seconds: 5)), now), isTrue);
      expect(isPortalSignalFresh(now.subtract(const Duration(seconds: 59)), now), isTrue);
      expect(isPortalSignalFresh(now.subtract(const Duration(minutes: 20)), now), isFalse);
    });

    test('a timestamp from the future is clock skew, not staleness', () {
      final now = DateTime(2026, 8, 24, 12);
      expect(isPortalSignalFresh(now.add(const Duration(seconds: 30)), now), isTrue);
    });

    test('a stale knock does not open anything', () async {
      final engine = await build();
      signals.emit(
        _signal(
          PortalSignalKind.knock,
          created: clock.now().subtract(const Duration(minutes: 20)),
        ),
      );
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('a stale accept does not open the camera', () async {
      final engine = await build();
      await engine.knock();
      signals.emit(
        _signal(
          PortalSignalKind.accept,
          created: clock.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await _settle();

      expect(engine.state, PortalState.knocking);
      expect(media.opened, isFalse);
      engine.dispose();
    });
  });

  group('consent gates the camera', () {
    test('knocking alone never touches media', () async {
      final engine = await build();
      await engine.knock();

      expect(engine.state, PortalState.knocking);
      expect(signals.sent, [PortalSignalKind.knock]);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('being knocked at alone never touches media', () async {
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();

      expect(engine.state, PortalState.knocked);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('accept is what opens it, and it offers when its id sorts first', () async {
      final engine = await build(me: 'aaa');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(engine.isOfferer, isTrue);
      expect(media.opened, isTrue);
      expect(signals.sent, [PortalSignalKind.accept, PortalSignalKind.offer]);
      expect(signals.payloads.last['sdp'], 'OFFER');
      engine.dispose();
    });

    test('the larger id waits for the offer instead of sending one', () async {
      final engine = await build(me: 'zzz');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      expect(engine.isOfferer, isFalse);
      expect(media.opened, isTrue);
      expect(signals.sent, [PortalSignalKind.accept]);
      expect(media.calls, isNot(contains('createOffer')));

      signals.emit(
        _signal(PortalSignalKind.offer, payload: {'sdp': 'THEIRS', 'type': 'offer'}),
      );
      await _settle();

      expect(media.remoteDescription, {'sdp': 'THEIRS', 'type': 'offer'});
      expect(signals.sent.last, PortalSignalKind.answer);
      expect(signals.payloads.last['sdp'], 'ANSWER');
      engine.dispose();
    });

    test('my knock plus their accept also connects', () async {
      final engine = await build(me: 'aaa');
      await engine.knock();
      signals.emit(_signal(PortalSignalKind.accept));
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(media.opened, isTrue);
      engine.dispose();
    });

    test('two simultaneous knocks are two consents, not a glare', () async {
      final engine = await build(me: 'aaa');
      await engine.knock();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(signals.sent, [
        PortalSignalKind.knock,
        PortalSignalKind.accept,
        PortalSignalKind.offer,
      ]);
      engine.dispose();
    });

    test('an empty TURN answer is fine — host candidates only', () async {
      turn.answer = const [];
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      expect(turn.calls, 1);
      expect(media.openedWith, isEmpty);
      expect(media.opened, isTrue);
      engine.dispose();
    });
  });

  group('ICE buffering', () {
    test('candidates arriving before the SDP are held, then replayed in order', () async {
      final engine = await build(me: 'zzz'); // answerer: offer comes to us
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      signals.emit(_signal(PortalSignalKind.ice, payload: {'candidate': 'one'}));
      signals.emit(_signal(PortalSignalKind.ice, payload: {'candidate': 'two'}));
      await _settle();
      expect(media.remoteCandidates, isEmpty);

      signals.emit(
        _signal(PortalSignalKind.offer, payload: {'sdp': 'THEIRS', 'type': 'offer'}),
      );
      await _settle();

      expect(media.remoteCandidates.map((c) => c['candidate']), ['one', 'two']);
      // The description has to land before any candidate does.
      expect(
        media.calls.indexOf('remoteDescription') < media.calls.indexOf('candidate'),
        isTrue,
      );
      engine.dispose();
    });

    test('candidates arriving after the SDP go straight through', () async {
      final engine = await build(me: 'zzz');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();
      signals.emit(
        _signal(PortalSignalKind.offer, payload: {'sdp': 'THEIRS', 'type': 'offer'}),
      );
      await _settle();

      signals.emit(_signal(PortalSignalKind.ice, payload: {'candidate': 'late'}));
      await _settle();

      expect(media.remoteCandidates.map((c) => c['candidate']), ['late']);
      engine.dispose();
    });

    test('an ICE signal outside a call is dropped, not buffered forever', () async {
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.ice, payload: {'candidate': 'ghost'}));
      await _settle();

      expect(media.calls, isEmpty);
      expect(engine.state, PortalState.idle);
      engine.dispose();
    });

    test('locally gathered candidates go out as ice signals', () async {
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      media.onLocalCandidate!({'candidate': 'mine', 'sdpMid': '0'});
      await _settle();

      expect(signals.sent.last, PortalSignalKind.ice);
      expect(signals.payloads.last['candidate'], 'mine');
      engine.dispose();
    });
  });

  group('teardown always releases the camera', () {
    Future<PortalEngine> connected({String me = 'aaa'}) async {
      final engine = await build(me: me);
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();
      media.onConnected!();
      await _settle();
      expect(engine.state, PortalState.connected);
      return engine;
    }

    test('hangUp closes and disposes the media and tells the partner', () async {
      final engine = await connected();
      await engine.hangUp();
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      // close before dispose, always — dispose drops the renderers, and a
      // renderer disposed while a track still feeds it is how you get a
      // camera that stays on.
      expect(media.calls.sublist(media.calls.length - 2), ['close', 'dispose']);
      expect(signals.sent.last, PortalSignalKind.hangup);
      engine.dispose();
    });

    test('a remote hangup tears down without echoing one back', () async {
      final engine = await connected();
      final before = signals.sent.length;
      signals.emit(_signal(PortalSignalKind.hangup));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      expect(signals.sent.length, before);
      engine.dispose();
    });

    test('a dead connection auto-hangs-up', () async {
      final engine = await connected();
      media.onLost!('ice failed');
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(media.closed, isTrue);
      expect(engine.lastError, isNotNull);
      expect(signals.sent.last, PortalSignalKind.hangup);
      engine.dispose();
    });

    test('a camera that refuses fails into idle with a message, not a crash', () async {
      media.openThrows = StateError('camera busy');
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNotNull);
      // Half-opened media still gets closed — that's the whole point.
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      engine.dispose();
    });

    test('a hang-up during a slow camera open still releases it', () async {
      // The permission-dialog window: the user accepts, the system prompt
      // sits there, and they change their mind and hang up. The engine's
      // queue makes the hang-up wait for the open to finish rather than
      // interleave with it — and then it tears the freshly-opened camera
      // straight back down, which is the behaviour that matters.
      media.openDelay = const Duration(milliseconds: 40);
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      final accepting = engine.accept();
      final hangingUp = engine.hangUp();
      await accepting;
      await hangingUp;
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(media.opened, isTrue);
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      engine.dispose();
    });

    test('dispose releases the camera and drops the subscription', () async {
      final engine = await connected();
      engine.dispose();
      await _settle();

      expect(media.disposed, isTrue);
      expect(signals.unsubscribed, 1);
    });

    test('an unanswered knock times out and closes itself', () async {
      final engine = await build(knockTimeout: const Duration(milliseconds: 5));
      await engine.knock();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNotNull);
      expect(signals.sent, [PortalSignalKind.knock, PortalSignalKind.hangup]);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('an incoming knock nobody answers lapses quietly', () async {
      final engine = await build(knockTimeout: const Duration(milliseconds: 5));
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(signals.sent, isEmpty);
      expect(engine.lastError, isNull);
      engine.dispose();
    });
  });

  group('one ice restart before giving up', () {
    /// Drives a call all the way to [PortalState.connected].
    Future<PortalEngine> connected({String me = 'aaa'}) async {
      final engine = await build(
        me: me,
        iceRestartTimeout: const Duration(milliseconds: 40),
      );
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();
      if (!engine.isOfferer) {
        signals.emit(
          _signal(
            PortalSignalKind.offer,
            payload: {'sdp': 'THEIRS', 'type': 'offer'},
          ),
        );
        await _settle();
      }
      media.onConnected!();
      await _settle();
      expect(engine.state, PortalState.connected);
      return engine;
    }

    test('the offering side restarts ice and re-offers', () async {
      final engine = await connected(me: 'aaa');
      media.onFailed!();
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(engine.isReconnecting, isTrue);
      expect(media.iceRestarts, 1);
      expect(media.calls, contains('createRestartOffer'));
      expect(signals.sent.last, PortalSignalKind.offer);
      expect(signals.payloads.last['sdp'], 'RESTART');
      // Still up: nothing was torn down while the restart is in flight.
      expect(media.closed, isFalse);
      engine.dispose();
    });

    test('a restart that reconnects goes back to connected', () async {
      final engine = await connected(me: 'aaa');
      media.onFailed!();
      await _settle();
      signals.emit(
        _signal(
          PortalSignalKind.answer,
          payload: {'sdp': 'THEIR-RESTART', 'type': 'answer'},
        ),
      );
      await _settle();
      media.onConnected!();
      await _settle();

      expect(engine.state, PortalState.connected);
      expect(engine.isReconnecting, isFalse);
      expect(media.closed, isFalse);
      engine.dispose();
    });

    test('the answering side waits rather than restarting itself', () async {
      final engine = await connected(me: 'zzz');
      final before = signals.sent.length;
      media.onFailed!();
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(engine.isReconnecting, isTrue);
      expect(media.iceRestarts, 0);
      expect(signals.sent.length, before, reason: 'nothing sent while waiting');

      signals.emit(
        _signal(
          PortalSignalKind.offer,
          payload: {'sdp': 'THEIR-RESTART', 'type': 'offer'},
        ),
      );
      await _settle();

      expect(media.remoteDescription, {
        'sdp': 'THEIR-RESTART',
        'type': 'offer',
      });
      expect(signals.sent.last, PortalSignalKind.answer);
      engine.dispose();
    });

    test('a restart offer arriving first half-closes the curtain', () async {
      // The answering side never saw `failed` itself — the only hint it
      // gets that anything went wrong is the renegotiation offer.
      final engine = await connected(me: 'zzz');
      signals.emit(
        _signal(
          PortalSignalKind.offer,
          payload: {'sdp': 'THEIR-RESTART', 'type': 'offer'},
        ),
      );
      await _settle();

      expect(engine.state, PortalState.connecting);
      expect(engine.isReconnecting, isTrue);
      expect(signals.sent.last, PortalSignalKind.answer);
      engine.dispose();
    });

    test('a restart that never lands tears the call down', () async {
      final engine = await connected(me: 'aaa');
      media.onFailed!();
      await _settle();
      expect(engine.state, PortalState.connecting);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNotNull);
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      expect(signals.sent.last, PortalSignalKind.hangup);
      engine.dispose();
    });

    test('a second failure is not a blip — no restart loop', () async {
      final engine = await connected(me: 'aaa');
      media.onFailed!();
      await _settle();
      signals.emit(
        _signal(
          PortalSignalKind.answer,
          payload: {'sdp': 'THEIR-RESTART', 'type': 'answer'},
        ),
      );
      await _settle();
      media.onConnected!();
      await _settle();
      expect(engine.state, PortalState.connected);

      media.onFailed!();
      await _settle();

      expect(media.iceRestarts, 1, reason: 'exactly one restart per call');
      expect(engine.state, PortalState.idle);
      expect(media.closed, isTrue);
      expect(media.disposed, isTrue);
      engine.dispose();
    });

    test('a fresh call gets its restart budget back', () async {
      final engine = await connected(me: 'aaa');
      media.onFailed!();
      await _settle();
      await engine.hangUp();
      await _settle();
      expect(engine.state, PortalState.idle);
      expect(engine.isReconnecting, isFalse);
      engine.dispose();
    });
  });

  group('saying no', () {
    test('decline answers and goes straight back to idle', () async {
      final engine = await build();
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.decline();

      expect(engine.state, PortalState.idle);
      expect(signals.sent, [PortalSignalKind.decline]);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('being declined ends the knock with a note', () async {
      final engine = await build();
      await engine.knock();
      signals.emit(_signal(PortalSignalKind.decline));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNotNull);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('a knock their accept answered never fires the timeout', () async {
      final engine = await build(knockTimeout: const Duration(milliseconds: 5));
      await engine.knock();
      signals.emit(_signal(PortalSignalKind.accept));
      await _settle();
      expect(engine.state, PortalState.connecting);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _settle();

      // The timer that guarded the knock must be disarmed the moment the
      // knock was answered — a live one here would tear down a working
      // call mid-handshake.
      expect(engine.state, PortalState.connecting);
      expect(media.closed, isFalse);
      engine.dispose();
    });

    test('a knock that cannot be sent fails into idle', () async {
      signals.failCreate = true;
      final engine = await build();
      await engine.knock();
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNotNull);
      engine.dispose();
    });
  });

  group('multi-device double-accept guard', () {
    test('my own accept from another device lapses knocked to idle', () async {
      final engine = await build(me: 'aaa');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      expect(engine.state, PortalState.knocked);

      signals.emitOwn(_signal(PortalSignalKind.accept, from: 'aaa'));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.partnerId, isNull);
      // The camera never opens here — the OTHER device is the one that
      // answered — and nothing gets echoed back to a partner who already
      // has their answer.
      expect(media.calls, isEmpty);
      expect(signals.sent, isEmpty);
      engine.dispose();
    });

    test('my own decline from another device also lapses quietly', () async {
      final engine = await build(me: 'aaa');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();

      signals.emitOwn(_signal(PortalSignalKind.decline, from: 'aaa'));
      await _settle();

      expect(engine.state, PortalState.idle);
      expect(engine.lastError, isNull);
      expect(media.calls, isEmpty);
      engine.dispose();
    });

    test('my own hangup from another device lapses knocked too', () async {
      final engine = await build(me: 'aaa');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();

      signals.emitOwn(_signal(PortalSignalKind.hangup, from: 'aaa'));
      await _settle();

      expect(engine.state, PortalState.idle);
      engine.dispose();
    });

    test('an own signal outside knocked is a no-op, not a crash', () async {
      final engine = await build(me: 'aaa');
      // Idle: nothing to lapse.
      signals.emitOwn(_signal(PortalSignalKind.accept, from: 'aaa'));
      await _settle();
      expect(engine.state, PortalState.idle);

      // Knocking (I sent the knock myself): my own accept from another
      // device isn't the "someone else already answered a knock at ME"
      // case, so it's ignored — the real accept still arrives as the
      // partner's normal (non-own) signal.
      await engine.knock();
      signals.emitOwn(_signal(PortalSignalKind.accept, from: 'aaa'));
      await _settle();
      expect(engine.state, PortalState.knocking);
      engine.dispose();
    });

    test('an own machinery signal (offer/answer/ice) is ignored', () async {
      final engine = await build(me: 'aaa');
      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();

      signals.emitOwn(
        _signal(
          PortalSignalKind.offer,
          from: 'aaa',
          payload: {'sdp': 'x', 'type': 'offer'},
        ),
      );
      await _settle();

      expect(engine.state, PortalState.knocked);
      engine.dispose();
    });
  });

  group('state notifications', () {
    test('every transition notifies exactly once', () async {
      final engine = await build();
      final seen = <PortalState>[];
      engine.addListener(() {
        if (seen.isEmpty || seen.last != engine.state) seen.add(engine.state);
      });

      signals.emit(_signal(PortalSignalKind.knock));
      await _settle();
      await engine.accept();
      await _settle();
      media.onConnected!();
      await _settle();
      await engine.hangUp();
      await _settle();

      expect(seen, [
        PortalState.knocked,
        PortalState.connecting,
        PortalState.connected,
        PortalState.closing,
        PortalState.idle,
      ]);
      engine.dispose();
    });
  });
}
