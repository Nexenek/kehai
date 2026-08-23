import 'presence_service.dart';

/// Windows/Android stand-in until platform-specific presence sources land.
/// Always reports [DevicePresence.empty] — the heartbeat still fires on
/// schedule, it just never carries `now_playing`/`idle_seconds` keys, which
/// is indistinguishable (per the "only provided keys are written" contract)
/// from those signals simply not being implemented yet.
///
/// - Windows: `GlobalSystemMediaTransportControlsSessionManager` (GSMTC)
///   for now-playing, `GetLastInputInfo()` for idle —
///   kb/platform-desktop.md's "Now-playing"/"Idle / presence" tables.
///   TODO(phase2b): implement once Windows builds are possible in this env.
/// - Android: now-playing/idle come from Android-side signals (a
///   `NotificationListenerService` media-session listener, `UsageStats`)
///   once the Android SDK is installed here.
///   TODO(phase2b): implement after Android SDK install.
class StubPresenceService implements PresenceService {
  const StubPresenceService();

  @override
  DevicePresence get current => DevicePresence.empty;

  @override
  Stream<DevicePresence> get onChange => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}
