import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../data/services/background/kehai_foreground_task.dart';
import '../../../../data/services/presence/android/android_presence_channel.dart';
import '../../../core/strings/app_strings.dart';

/// State for the "phone superpowers" screen: the live grant status of each
/// optional Android capability, plus the actions that ask for them.
///
/// Nothing here is required. Every grant maps to one presence signal, and
/// a denial means that signal is simply never reported — the heartbeat
/// keeps running, the partner card just has less to say. That's why this
/// is a settings screen with per-item buttons rather than a gate on
/// startup.
class PhoneSuperpowersViewModel extends ChangeNotifier {
  PhoneSuperpowersViewModel({
    AndroidPresenceChannel presenceChannel = const AndroidPresenceChannel(),
    required bool initialShareFocusedApp,
    required bool initialShareUnknownApps,
    required bool initialShareLocation,
    required Future<void> Function(bool value) onSetShareFocusedApp,
    required Future<void> Function(bool value) onSetShareUnknownApps,
    required Future<void> Function(bool value) onSetShareLocation,
  }) : _presenceChannel = presenceChannel,
       _onSetShareFocusedApp = onSetShareFocusedApp,
       _onSetShareUnknownApps = onSetShareUnknownApps,
       _onSetShareLocation = onSetShareLocation {
    shareFocusedApp = initialShareFocusedApp;
    shareUnknownApps = initialShareUnknownApps;
    shareLocation = initialShareLocation;
  }

  final AndroidPresenceChannel _presenceChannel;

  /// Persistence + pushing the value into the live presence service both
  /// live on `AppController` (the one place that owns the presence
  /// service), so this class stays a thin, easily-fake-able callback
  /// wrapper rather than duplicating that logic — same shape as
  /// [SharingSettingsViewModel] on desktop.
  final Future<void> Function(bool value) _onSetShareFocusedApp;
  final Future<void> Function(bool value) _onSetShareUnknownApps;

  /// Same shape again for `shareLocation` — `AppController` also owns
  /// [LocationPublisher] (the live thing this toggle actually starts/stops).
  final Future<void> Function(bool value) _onSetShareLocation;

  bool get isSupported => KehaiForegroundTask.isSupported;

  bool isLoading = true;
  bool notificationsGranted = false;
  bool batteryExempt = false;
  bool listenerEnabled = false;
  bool serviceRunning = false;
  bool usageAccessGranted = false;

  /// The raw OS grant — kept as the full enum rather than a bool because
  /// the location row is the one honest two-step flow on this screen: a
  /// user who only granted "while using" is meaningfully different from
  /// one who granted "all the time", and the UI needs to tell them apart
  /// (kb/platform-android.md: "foreground grant → explain value →
  /// background grant").
  LocationPermission locationPermission = LocationPermission.denied;

  bool get locationWhileInUseGranted =>
      locationPermission == LocationPermission.whileInUse ||
      locationPermission == LocationPermission.always;

  bool get locationAlwaysGranted =>
      locationPermission == LocationPermission.always;

  /// The `shareFocusedApp`/`shareUnknownApps`/`shareLocation` opt-ins
  /// (kb/features.md "Focused-app status", kb/contracts.md "Location") —
  /// plain preference state, not a live grant, so unlike the rows above
  /// these aren't re-read in [refresh]; they only change when the user
  /// taps their own toggle.
  bool shareFocusedApp = false;
  bool shareUnknownApps = false;
  bool shareLocation = false;

  /// A transient one-liner for the rare "your ROM hides that screen" case.
  String? message;

  Future<void> refresh() async {
    if (!isSupported) {
      isLoading = false;
      notifyListeners();
      return;
    }

    final results = await Future.wait([
      KehaiForegroundTask.hasNotificationPermission,
      KehaiForegroundTask.isIgnoringBatteryOptimizations,
      _presenceChannel.isNotificationListenerEnabled(),
      KehaiForegroundTask.isRunning,
      _presenceChannel.hasUsageAccess(),
    ]);

    notificationsGranted = results[0];
    batteryExempt = results[1];
    listenerEnabled = results[2];
    serviceRunning = results[3];
    usageAccessGranted = results[4];
    try {
      locationPermission = await Geolocator.checkPermission();
    } catch (_) {
      locationPermission = LocationPermission.denied;
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> requestNotifications() async {
    await KehaiForegroundTask.requestNotificationPermission();
    await refresh();
  }

  Future<void> requestBatteryExemption() async {
    await KehaiForegroundTask.requestBatteryExemption();
    await refresh();
  }

  /// The listener grant can't be requested in-app — it's a special access
  /// screen the user has to walk to. We open it and re-check when they
  /// come back (the screen calls [refresh] on resume).
  Future<void> openListenerSettings() async {
    final opened = await _presenceChannel.openNotificationListenerSettings();
    if (!opened) {
      message = AppStrings.superpowersOpenSettingsFailed;
      notifyListeners();
    }
  }

  /// Same "walk to a special-access screen, re-check on resume" shape as
  /// [openListenerSettings] — Usage Access can't be requested in-app either.
  Future<void> openUsageAccessSettings() async {
    final opened = await _presenceChannel.openUsageAccessSettings();
    if (!opened) {
      message = AppStrings.superpowersOpenSettingsFailed;
      notifyListeners();
    }
  }

  /// Step one of the honest two-step location flow: the normal runtime
  /// prompt, which on modern Android only ever grants "while using the
  /// app" no matter what's asked for — "all the time" always needs the
  /// separate [openLocationAlwaysSettings] step.
  Future<void> requestLocationWhileInUse() async {
    try {
      await Geolocator.requestPermission();
    } catch (_) {
      // Denied, or the platform has no location plugin registered — either
      // way [refresh] below reflects reality.
    }
    await refresh();
  }

  /// Step two: "allow all the time" isn't grantable through a dialog once
  /// "while using" is already set, so — same "walk to a system screen,
  /// re-check on resume" shape as [openListenerSettings] — this opens the
  /// app's own settings page for the user to flip it there.
  Future<void> openLocationAlwaysSettings() async {
    final opened = await Geolocator.openAppSettings();
    if (!opened) {
      message = AppStrings.superpowersOpenSettingsFailed;
      notifyListeners();
    }
  }

  Future<void> setShareFocusedApp(bool value) async {
    shareFocusedApp = value;
    await _onSetShareFocusedApp(value);
    notifyListeners();
  }

  Future<void> setShareUnknownApps(bool value) async {
    shareUnknownApps = value;
    await _onSetShareUnknownApps(value);
    notifyListeners();
  }

  /// The "share my location ♡" opt-in (kb/contracts.md "Location"). A
  /// preference like [shareFocusedApp], not a live OS grant — it can be on
  /// with no location permission yet, in which case
  /// `LocationPublisher.setEnabled` just waits quietly until
  /// [requestLocationWhileInUse]/[openLocationAlwaysSettings] catch up.
  Future<void> setShareLocation(bool value) async {
    shareLocation = value;
    await _onSetShareLocation(value);
    notifyListeners();
  }

  Future<void> toggleService() async {
    if (serviceRunning) {
      await KehaiForegroundTask.stop();
    } else {
      await KehaiForegroundTask.start();
    }
    await refresh();
  }

  void clearMessage() {
    if (message == null) return;
    message = null;
    notifyListeners();
  }
}
