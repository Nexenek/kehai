import 'package:flutter/services.dart';

/// The thin Dart half of the `app.kehai/presence` platform channels. Holds
/// no logic beyond "call the channel, don't throw" — everything worth
/// testing lives in `android_presence_mapper.dart`.
///
/// The Kotlin half is registered on BOTH Flutter engines (the UI one from
/// `MainActivity.configureFlutterEngine`, the foreground-service one from
/// `KehaiApplication`'s task lifecycle listener), so these calls work
/// identically in the app isolate and in the background task isolate.
class AndroidPresenceChannel {
  const AndroidPresenceChannel();

  static const _methods = MethodChannel('app.kehai/presence');
  static const _events = EventChannel('app.kehai/presence_events');

  /// Fires whenever any watched signal changes (battery, charging, screen
  /// on/off, unlock, media session/metadata/playback). Payload shape is
  /// documented on `AndroidPresenceSnapshot.fromChannel`.
  Stream<Object?> get events => _events.receiveBroadcastStream();

  /// One-shot read of the same payload — used to seed state before the
  /// first event arrives.
  Future<Object?> snapshot() => _invoke<Object?>('getSnapshot');

  /// Whether the user has ticked Kehai in Settings > Notification access.
  /// Without it, `MediaSessionManager.getActiveSessions` throws and
  /// now-playing is simply absent (kb/platform-android.md "Now-playing").
  Future<bool> isNotificationListenerEnabled() async =>
      await _invoke<bool>('isNotificationListenerEnabled') ?? false;

  /// Deep-links to Settings > Notification access. Returns false if the
  /// screen doesn't exist on this ROM (some do hide it).
  Future<bool> openNotificationListenerSettings() async =>
      await _invoke<bool>('openNotificationListenerSettings') ?? false;

  /// Whether the user has granted Kehai the Usage Access special access
  /// (`AppOpsManager` op `GET_USAGE_STATS`) — the grant
  /// `PresenceMonitor.queryForegroundPackage` needs before it can read
  /// `UsageStatsManager` at all (kb/platform-android.md "Foreground app").
  Future<bool> hasUsageAccess() async =>
      await _invoke<bool>('hasUsageAccess') ?? false;

  /// Deep-links to Settings > Apps > Special app access > Usage access.
  /// Returns false if the screen doesn't exist on this ROM.
  Future<bool> openUsageAccessSettings() async =>
      await _invoke<bool>('openUsageAccessSettings') ?? false;

  /// Tells the native side whether it's allowed to poll
  /// `UsageStatsManager` for the foreground app at all — the
  /// `shareFocusedApp` opt-in, pushed down so "off" means the OS is never
  /// even asked, not just that Dart discards the answer. Swallowed on
  /// failure like every other call here: a missed toggle just means the
  /// next one (or the next app launch) catches it up.
  Future<void> setForegroundAppEnabled(bool enabled) async {
    try {
      await _methods.invokeMethod<void>('setForegroundAppEnabled', {
        'enabled': enabled,
      });
    } catch (_) {
      // No channel (tests, non-Android) or a native-side hiccup — the next
      // toggle flip retries.
    }
  }

  /// One-shot raw read of the current foreground package — gated on the
  /// Usage Access OS grant only, NOT on [setForegroundAppEnabled] — so the
  /// "phone superpowers" screen can preview "what we'd share right now"
  /// (kb/features.md "Focused-app status") before the user turns
  /// `shareFocusedApp` on. Never run through `ActivityMapper` here; that's
  /// the caller's job, same as `WindowsPresenceService.getForegroundApp`.
  Future<String?> getForegroundAppPreview() =>
      _invoke<String>('getForegroundAppPreview');

  /// Every call is swallowed on failure: on a device where a signal isn't
  /// available (or the plugin isn't attached to this engine yet) the
  /// answer is "no reading", never an exception bubbling into the
  /// heartbeat loop.
  Future<T?> _invoke<T>(String method) async {
    try {
      return await _methods.invokeMethod<T>(method);
    } catch (_) {
      return null;
    }
  }
}
