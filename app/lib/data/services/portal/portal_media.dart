import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'portal_log.dart';

/// ICE server maps exactly as `RTCPeerConnection` wants them — see
/// [TurnRepository], which is where they come from.
typedef IceServers = List<Map<String, dynamic>>;

/// THE SEAM.
///
/// Everything in a portal call that needs the native WebRTC stack lives
/// behind this one interface: the peer connection, the camera and
/// microphone, the two video renderers. [PortalEngine] holds one of these
/// and nothing else from `flutter_webrtc`, so the whole state machine —
/// who offers, what a knock means, when a signal is too old to honour, and
/// (most importantly) every path that must release the camera — runs in a
/// plain `flutter test` against a fake.
///
/// That matters because none of the native side can run in a test: the
/// plugin's method channel has no implementation in the test binary, and
/// `getUserMedia` would want a real camera. Splitting here means the part
/// that can only be verified on real hardware is deliberately thin and
/// almost branch-free ([WebRtcPortalMedia] below), while the part with all
/// the decisions in it is fully covered.
///
/// Lifecycle contract implementations must honour:
///   * [open] is the ONLY method that may touch the camera or microphone.
///     The engine calls it strictly after both people have consented — the
///     curtain rule (kb/decisions.md ADR-9: no silent watching, ever).
///   * [close] releases capture devices and must be safe to call at any
///     time, any number of times, including after a half-failed [open].
///   * [dispose] is [close] plus the renderers, and ends the object's life.
abstract class PortalMedia {
  /// Fired for every ICE candidate this peer gathers; the engine forwards
  /// each one as an `ice` signal (trickle ICE — candidates go out as they
  /// are found rather than waiting for gathering to finish).
  void Function(Map<String, dynamic> candidate)? onLocalCandidate;

  /// Fired once the peer connection actually carries media — on the first
  /// connect AND again after a successful ICE restart, which is what lets
  /// the engine use one handler for both.
  void Function()? onConnected;

  /// Fired when ICE gave up on every candidate pair it had.
  ///
  /// Recoverable, which is why it is separate from [onLost]: `failed` is
  /// routinely what a network change looks like from inside the ICE agent
  /// (wifi→cellular, a route flipping between a tailnet and the LAN both
  /// devices are actually sitting on), and an ICE restart re-gathers from
  /// scratch and frequently fixes it. The engine tries exactly one before
  /// giving up.
  void Function()? onFailed;

  /// Fired when the connection is definitively gone — the peer connection
  /// closed under us. Nothing to restart; the engine hangs up so the camera
  /// never outlives the call.
  void Function(String reason)? onLost;

  /// Live preview of my own camera. Null until [open] has run — which is
  /// the honest thing for the UI to show, since before that there is
  /// genuinely nothing looking at me.
  RTCVideoRenderer? get localRenderer;

  /// The partner's stream. Same nullability rule.
  RTCVideoRenderer? get remoteRenderer;

  /// Builds the peer connection and opens the camera + mic. Throws on
  /// denial or hardware failure; the engine catches and tears down.
  Future<void> open(IceServers iceServers);

  /// `{sdp, type}`, with the local description already set.
  ///
  /// [iceRestart] asks for a fresh ICE ufrag/pwd, i.e. "throw away every
  /// candidate pair we tried and gather again". Only the offering peer ever
  /// passes it.
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false});

  /// Tells the ICE agent to re-gather. Paired with
  /// `createOffer(iceRestart: true)` — this on its own only arms the
  /// restart; the offer is what carries it to the other side.
  Future<void> restartIce();

  /// Same, for the answering side. Only valid after
  /// [acceptRemoteDescription].
  Future<Map<String, dynamic>> createAnswer();

  Future<void> acceptRemoteDescription(Map<String, dynamic> description);

  /// Only ever called after the remote description is in place — the engine
  /// buffers candidates that arrive early rather than pushing them here.
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate);

  /// Stops every track, drops the peer connection, blanks the renderers.
  /// Idempotent, and never throws.
  Future<void> close();

  /// [close] plus renderer disposal. The object is finished afterwards.
  Future<void> dispose();
}

/// The real thing: `flutter_webrtc` wired to the contract above.
///
/// Kept as small and as straight-line as it possibly can be — every `if` in
/// here is an `if` no test can reach. All the interesting decisions live in
/// [PortalEngine] on the other side of the seam.
class WebRtcPortalMedia extends PortalMedia {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCVideoRenderer? _local;
  RTCVideoRenderer? _remote;
  bool _closing = false;

  @override
  RTCVideoRenderer? get localRenderer => _local;

  @override
  RTCVideoRenderer? get remoteRenderer => _remote;

  /// 640×480 at 30fps: a window into a room, not a film shoot. Small enough
  /// that a phone on mobile data and a laptop on home wifi both carry it
  /// without the encoder thrashing, and — since this thing is meant to be
  /// left open for hours — small enough not to cook the phone.
  static const _mediaConstraints = <String, dynamic>{
    'audio': true,
    'video': {
      // The selfie camera. `facingMode` is a hint the desktop backends
      // ignore (they just take the default device), which is the right
      // behaviour there.
      'facingMode': 'user',
      'width': {'ideal': 640},
      'height': {'ideal': 480},
      'frameRate': {'ideal': 30},
    },
  };

  @override
  Future<void> open(IceServers iceServers) async {
    // Renderers first and separately from the camera: initializing a
    // renderer allocates a texture, it doesn't look at anybody.
    final local = _local ??= RTCVideoRenderer();
    final remote = _remote ??= RTCVideoRenderer();
    await local.initialize();
    await remote.initialize();

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      // Unified plan is the only semantics current libwebrtc really
      // supports; naming it keeps every platform on the same one.
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    portalLog(
      'peer connection created with ${iceServers.length} ice server(s)'
      '${iceServers.isEmpty ? ' — host candidates only, by design' : ''}',
    );

    pc.onIceCandidate = (candidate) {
      if (_closing) return;
      portalTrace(
        () =>
            'local candidate ${portalCandidateType(candidate.candidate)} '
            '${portalCandidateFingerprint(candidate.candidate)} '
            'mid=${candidate.sdpMid}',
      );
      // Spelled out rather than `candidate.toMap()`, which is typed
      // `dynamic` upstream — this is the exact JSON the other side's
      // [addRemoteCandidate] reads back.
      onLocalCandidate?.call({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    pc.onTrack = (event) {
      if (_closing) return;
      portalLog('remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) remote.srcObject = event.streams.first;
    };
    pc.onIceGatheringState = (state) {
      if (_closing) return;
      portalLog('ice gathering: ${_shortState(state.name)}');
    };
    // More granular than the peer-connection state, and it moves first:
    // `checking → connected → disconnected → failed` shows whether pairs
    // were ever tried at all, which is the difference between "no route"
    // and "route died".
    pc.onIceConnectionState = (state) {
      if (_closing) return;
      portalLog('ice connection: ${_shortState(state.name)}');
    };
    pc.onConnectionState = (state) {
      if (_closing) return;
      portalLog('peer connection: ${_shortState(state.name)}');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          unawaited(_logSelectedPair('connected'));
          onConnected?.call();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // Recoverable — see [onFailed]. The summary is logged before the
          // engine is told, so the "why" is in the log above whatever it
          // decides to do next.
          unawaited(
            _logSelectedPair('failed').whenComplete(() {
              if (!_closing) onFailed?.call();
            }),
          );
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          onLost?.call('the connection dropped');
        // `disconnected` is routinely transient (a wifi hiccup, a handover)
        // and recovers on its own; only `failed` is worth acting on.
        default:
          break;
      }
    };

    // THE camera moment. Nothing above this line opened a capture device.
    final stream = await navigator.mediaDevices.getUserMedia(
      _mediaConstraints,
    );
    _localStream = stream;
    local.srcObject = stream;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    final pc = _requirePc();
    final offer = await pc.createOffer(
      iceRestart ? const {'iceRestart': true} : const {},
    );
    await pc.setLocalDescription(offer);
    portalLog(iceRestart ? 'sent restart offer' : 'sent offer');
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  @override
  Future<void> restartIce() async {
    portalLog('restarting ice');
    await _requirePc().restartIce();
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    final pc = _requirePc();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    portalLog('sent answer');
    return {'sdp': answer.sdp, 'type': answer.type};
  }

  @override
  Future<void> acceptRemoteDescription(
    Map<String, dynamic> description,
  ) async {
    portalLog('accepted remote ${description['type']}');
    await _requirePc().setRemoteDescription(
      RTCSessionDescription(
        description['sdp'] as String?,
        description['type'] as String?,
      ),
    );
  }

  @override
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    final line = candidate['candidate'] as String?;
    portalTrace(
      () =>
          'remote candidate ${portalCandidateType(line)} '
          '${portalCandidateFingerprint(line)} mid=${candidate['sdpMid']}',
    );
    await _requirePc().addCandidate(
      RTCIceCandidate(
        line,
        candidate['sdpMid'] as String?,
        (candidate['sdpMLineIndex'] as num?)?.toInt(),
      ),
    );
  }

  /// One line saying which pair of candidate types actually got picked (or
  /// that none did). This is the single most useful thing in the whole log:
  /// `local=host remote=host` on a call that then fails says the two
  /// machines found a route and lost it, while no succeeded pair at all
  /// says they never had one — completely different problems.
  Future<void> _logSelectedPair(String moment) async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final reports = await pc.getStats();
      final byId = {for (final r in reports) r.id: r};
      StatsReport? chosen;
      for (final report in reports) {
        if (report.type != 'candidate-pair') continue;
        final values = report.values;
        if (values['state'] != 'succeeded') continue;
        // Prefer the nominated/selected pair; fall back to any succeeded
        // one, since not every platform reports the same flag.
        chosen ??= report;
        if (values['nominated'] == true || values['selected'] == true) {
          chosen = report;
          break;
        }
      }
      if (chosen == null) {
        portalLog('$moment: no succeeded candidate pair — no route was found');
        return;
      }
      final values = chosen.values;
      final local = byId[values['localCandidateId']]?.values['candidateType'];
      final remote = byId[values['remoteCandidateId']]?.values['candidateType'];
      portalLog(
        '$moment: selected pair local=$local remote=$remote '
        'state=${values['state']} nominated=${values['nominated']}',
      );
    } catch (e) {
      portalLog('$moment: stats unavailable ($e)');
    }
  }

  /// `RTCPeerConnectionStateFailed` → `failed`. The enum names carry the
  /// whole class name on every value, which makes a log four times wider
  /// than the thing it's saying.
  static String _shortState(String name) {
    for (final prefix in const [
      'RTCPeerConnectionState',
      'RTCIceConnectionState',
      'RTCIceGatheringState',
    ]) {
      if (name.startsWith(prefix)) return name.substring(prefix.length);
    }
    return name;
  }

  RTCPeerConnection _requirePc() {
    final pc = _pc;
    if (pc == null) throw StateError('portal peer connection is not open');
    return pc;
  }

  /// The trust anchor. Every step is individually guarded because a failure
  /// halfway through must not leave the camera light on — if disposing the
  /// stream throws, the tracks have already been stopped, and if the peer
  /// connection refuses to close, that's a leaked object, not a leaked
  /// camera.
  @override
  Future<void> close() async {
    _closing = true;

    // Detach the handlers before anything else: a candidate or state change
    // arriving mid-teardown would otherwise call back into an engine that
    // has already moved on.
    final pc = _pc;
    _pc = null;
    pc?.onIceCandidate = null;
    pc?.onTrack = null;
    pc?.onConnectionState = null;
    pc?.onIceConnectionState = null;
    pc?.onIceGatheringState = null;

    // Capture devices FIRST — before the renderers, before the connection.
    // This is the line that turns the camera light off, and nothing above
    // it may be able to throw past it.
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {
          // Already stopped, or the platform lost the handle. The device is
          // released either way; there is nothing useful to do here.
        }
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }

    try {
      _local?.srcObject = null;
    } catch (_) {}
    try {
      _remote?.srcObject = null;
    } catch (_) {}

    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    _closing = false;
  }

  @override
  Future<void> dispose() async {
    await close();
    final local = _local;
    final remote = _remote;
    _local = null;
    _remote = null;
    try {
      await local?.dispose();
    } catch (_) {}
    try {
      await remote?.dispose();
    } catch (_) {}
  }
}
