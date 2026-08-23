import 'dart:async';

import '../presence_service.dart';
import 'android_presence_channel.dart';
import 'android_presence_mapper.dart';

/// Android implementation of [PresenceService], replacing the old
/// Android arm of [StubPresenceService]. Reads three native signals
/// (kb/platform-android.md "Presence / status signals"):
///
/// - **battery + charging** — `ACTION_BATTERY_CHANGED` sticky broadcast,
///   runtime-registered. No permission.
/// - **screen state** — `ACTION_SCREEN_ON`/`ACTION_SCREEN_OFF` +
///   `ACTION_USER_PRESENT`, turned into the desktop path's
///   `idle_seconds` by measuring how long the screen has been off (screen
///   on = idle 0). No permission.
/// - **now-playing** — `MediaSessionManager.getActiveSessions`, gated on
///   the user enabling our `NotificationListenerService`.
///
/// Each source degrades independently: no listener grant just means
/// `now_playing` is never written, and the other two keep flowing.
///
/// Idle is *derived*, not pushed: the native side only tells us when the
/// screen went off, and [current] recomputes the elapsed seconds on every
/// read. That way a 30s heartbeat tick sees idle climb 30, 60, 90… with no
/// native timer running in the background.
class AndroidPresenceService implements PresenceService {
  AndroidPresenceService({
    AndroidPresenceChannel channel = const AndroidPresenceChannel(),
    DateTime Function() now = DateTime.now,
  }) : _channel = channel,
       _now = now;

  final AndroidPresenceChannel _channel;
  final DateTime Function() _now;

  final _controller = StreamController<DevicePresence>.broadcast();
  StreamSubscription<Object?>? _eventSub;
  AndroidPresenceSnapshot _snapshot = AndroidPresenceSnapshot.empty;
  bool _started = false;

  /// Until the first native reading lands, [AndroidPresenceSnapshot.empty]
  /// would claim "screen on, so idle 0" — a made-up fact. Report nothing
  /// at all instead; the contract's "absent key" is honest, a zero isn't.
  bool _hasReading = false;

  /// The latest raw reading — the "phone superpowers" screen uses this to
  /// show whether the notification-listener grant is actually producing
  /// media sessions, rather than just claiming the toggle is on.
  AndroidPresenceSnapshot get snapshot => _snapshot;

  @override
  DevicePresence get current => _hasReading
      ? _snapshot.toPresence(now: _now())
      : DevicePresence.empty;

  @override
  Stream<DevicePresence> get onChange => _controller.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _eventSub = _channel.events.listen(
      _onEvent,
      // A dropped EventChannel (engine teardown, plugin detach) leaves the
      // last snapshot in place rather than crashing the heartbeat.
      onError: (Object _) {},
      cancelOnError: false,
    );

    _applySnapshot(
      AndroidPresenceSnapshot.fromChannel(await _channel.snapshot()),
    );
  }

  void _onEvent(Object? raw) =>
      _applySnapshot(AndroidPresenceSnapshot.fromChannel(raw));

  void _applySnapshot(AndroidPresenceSnapshot next) {
    final before = current;
    _snapshot = next;
    _hasReading = true;
    final after = current;
    if (after != before && !_controller.isClosed) _controller.add(after);
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    _started = false;
    _hasReading = false;
    await _controller.close();
  }
}
