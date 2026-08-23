import 'dart:async';

import '../../../../domain/activity_mapper.dart';
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

  /// The `shareFocusedApp` per-device opt-in (kb/features.md "Focused-app
  /// status"). Off by default; setting it pushes the same value down to the
  /// native side via [AndroidPresenceChannel.setForegroundAppEnabled] so
  /// "off" means `UsageStatsManager` is never even polled, not just that
  /// Dart ignores `foreground_package`. Set by `AppController` from
  /// `PrefsService` on launch and again whenever the phone-superpowers
  /// screen's toggle changes.
  bool get shareFocusedApp => _shareFocusedApp;
  bool _shareFocusedApp = false;

  set shareFocusedApp(bool value) {
    if (_shareFocusedApp == value) return;
    final before = current;
    _shareFocusedApp = value;
    unawaited(_channel.setForegroundAppEnabled(value));
    _notifyIfChanged(before);
  }

  /// The `shareUnknownApps` opt-in: an app with no `ActivityMapper` entry
  /// still gets a cleaned-up guess instead of staying silent. Meaningless —
  /// and never consulted — while [shareFocusedApp] is off. Purely a Dart
  /// concern, so unlike [shareFocusedApp] this never touches the channel.
  bool get shareUnknownApps => _shareUnknownApps;
  bool _shareUnknownApps = false;

  set shareUnknownApps(bool value) {
    if (_shareUnknownApps == value) return;
    final before = current;
    _shareUnknownApps = value;
    _notifyIfChanged(before);
  }

  @override
  DevicePresence get current {
    if (!_hasReading) return DevicePresence.empty;
    final activity = _shareFocusedApp
        ? ActivityMapper.mapAndroidPackage(
            _snapshot.foregroundPackage,
            shareUnknown: _shareUnknownApps,
          )
        : null;
    return _snapshot.toPresence(now: _now(), activity: activity);
  }

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
    _notifyIfChanged(before);
  }

  /// Pushes [current] to [onChange] iff it differs from [before] — shared by
  /// [_applySnapshot] and the [shareFocusedApp]/[shareUnknownApps] setters,
  /// none of which should invent a reading: on a service with no
  /// [_hasReading] yet, [current] stays [DevicePresence.empty] on both sides
  /// of the comparison, so flipping a toggle before the first native
  /// snapshot arrives is a no-op here, same as it would be for any other
  /// field.
  void _notifyIfChanged(DevicePresence before) {
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
