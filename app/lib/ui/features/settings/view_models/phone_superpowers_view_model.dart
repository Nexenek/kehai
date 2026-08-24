import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../data/services/background/kehai_foreground_task.dart';
import '../../../../data/services/presence/android/android_presence_channel.dart';
import '../../../../data/services/presence/android/vitals_channel.dart';
import '../../../../domain/activity_mapper.dart';
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
    VitalsChannel vitalsChannel = const VitalsChannel(),
    required bool initialShareFocusedApp,
    required bool initialShareUnknownApps,
    required bool initialShareLocation,
    required bool initialShareVitals,
    required Future<void> Function(bool value) onSetShareFocusedApp,
    required Future<void> Function(bool value) onSetShareUnknownApps,
    required Future<void> Function(bool value) onSetShareLocation,
    required Future<void> Function(bool value) onSetShareVitals,
    @visibleForTesting
    Duration activityPreviewInterval = const Duration(seconds: 3),
    // Everything on this screen is Android-only, so off Android the whole
    // view model short-circuits — which would leave the vitals states below
    // untestable anywhere CI runs. This is the seam that lets a test pretend
    // it's on a phone; nothing else ever passes it.
    @visibleForTesting bool? isSupportedOverride,
  }) : _presenceChannel = presenceChannel,
       _isSupportedOverride = isSupportedOverride,
       _vitalsChannel = vitalsChannel,
       _onSetShareFocusedApp = onSetShareFocusedApp,
       _onSetShareUnknownApps = onSetShareUnknownApps,
       _onSetShareLocation = onSetShareLocation,
       _onSetShareVitals = onSetShareVitals {
    shareFocusedApp = initialShareFocusedApp;
    shareUnknownApps = initialShareUnknownApps;
    shareLocation = initialShareLocation;
    shareVitals = initialShareVitals;
    // Show something sensible before the first async probe/refresh lands.
    activityPreview = resolvePreviewMessage(
      shareFocusedApp: shareFocusedApp,
      hasUsageAccess: false,
      hasReading: false,
      mappedLabel: null,
    );
    unawaited(_refreshActivityPreview());
    _activityPreviewTimer = Timer.periodic(
      activityPreviewInterval,
      (_) => unawaited(_refreshActivityPreview()),
    );
  }

  final AndroidPresenceChannel _presenceChannel;
  final VitalsChannel _vitalsChannel;
  final bool? _isSupportedOverride;

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

  /// And again for `shareVitals` — `AppController` owns the [VitalsService]
  /// this toggle switches on, and the nudge that gets it to the background
  /// isolate.
  final Future<void> Function(bool value) _onSetShareVitals;

  bool get isSupported =>
      _isSupportedOverride ?? KehaiForegroundTask.isSupported;

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

  /// The `shareVitals` opt-in (kb/platform-android.md "Steps / heart
  /// rate"). Unlike its neighbours this one has an OS grant behind it, so
  /// the three fields below travel with it.
  bool shareVitals = false;

  /// Whether Health Connect exists on this phone at all. Starts
  /// [VitalsAvailability.unavailable] so the row can't offer a grant that
  /// would fail before the first [refresh] lands.
  VitalsAvailability vitalsAvailability = VitalsAvailability.unavailable;

  /// READ_STEPS + READ_HEART_RATE, as Health Connect currently sees them.
  bool vitalsGranted = false;

  /// Whether the last probe read anything at all. Health Connect being
  /// connected doesn't mean there's data in it — a watch that hasn't synced
  /// today leaves the whole feature silent, and saying so ([AppStrings
  /// .vitalsNoData]) beats the partner card just never mentioning a heart.
  bool vitalsHasData = false;

  /// READ_HEALTH_DATA_IN_BACKGROUND, tracked separately from [vitalsGranted]
  /// because it's the difference between a feature that works and one that
  /// only works while you're looking at it — and the user has no way to
  /// guess which they've got unless the row says so.
  bool vitalsBackgroundGranted = false;

  /// The row's own status line: the grant fallback after a request that
  /// couldn't open a sheet, or the honest "foreground only" warning. Null
  /// when there's nothing to explain. Separate from [message] (the screen's
  /// shared one-liner) so it can sit inside the vitals window, next to the
  /// thing it's about.
  String? vitalsMessage;

  /// "There's nothing here to connect to" — [VitalsAvailability.needsUpdate]
  /// counts, since we can't do the updating for them either.
  bool get vitalsUnavailable =>
      vitalsAvailability != VitalsAvailability.available;

  /// Opted in, granted, and Health Connect still has nothing for us — the
  /// [AppStrings.vitalsNoData] state.
  bool get vitalsWaitingForData =>
      shareVitals && vitalsGranted && !vitalsHasData;

  /// Working, but only while the app is on screen. The row shows this with
  /// a way to fix it rather than letting the partner's card quietly go
  /// stale for hours (the reported "updates super rarely if at all").
  bool get vitalsForegroundOnly =>
      shareVitals && vitalsGranted && !vitalsBackgroundGranted;

  /// Whether the row should offer its "open health connect ⚙︎" button —
  /// for either fixable state: a grant we couldn't ask for, or background
  /// access we didn't get.
  bool get vitalsCanOpenSettings =>
      !vitalsUnavailable && (!vitalsGranted || vitalsForegroundOnly);

  Timer? _activityPreviewTimer;

  /// "What we'd share right now" for the `shareFocusedApp` window —
  /// kb/features.md "Focused-app status"'s silent-failure fix. Refreshed
  /// every [PhoneSuperpowersViewModel]'s `activityPreviewInterval` (default
  /// ~3s) from [AndroidPresenceChannel.getForegroundAppPreview], a raw
  /// probe gated only on the Usage Access OS grant — NOT on
  /// [shareFocusedApp] — so this works even before the user turns the
  /// opt-in on, same as the desktop dialog's preview.
  String activityPreview = '';

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
    await _refreshVitals();
    final wasGranted = locationWhileInUseGranted;
    try {
      locationPermission = await Geolocator.checkPermission();
    } catch (_) {
      locationPermission = LocationPermission.denied;
    }
    isLoading = false;
    notifyListeners();

    // Grant flipped while we were away (the settings-page path of the
    // two-step flow): bounce the service so it picks up the location
    // foreground-service type.
    if (!wasGranted && locationWhileInUseGranted && shareLocation) {
      await _restartServiceForLocation();
    }

    // Usage Access is itself a "walk to system settings and back" grant
    // (see [openUsageAccessSettings]) — [refresh] is exactly the moment
    // that could have changed, so the preview should reflect it right away
    // rather than waiting up to ~3s.
    await _refreshActivityPreview();
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
    await _refreshActivityPreview();
  }

  Future<void> setShareUnknownApps(bool value) async {
    shareUnknownApps = value;
    await _onSetShareUnknownApps(value);
    notifyListeners();
    await _refreshActivityPreview();
  }

  /// The "share heartbeat & steps ♥︎" opt-in. Turning it ON when the OS
  /// grant is missing walks straight into Health Connect's permission sheet
  /// first — a toggle that says "on" while the phone can't read anything
  /// would be a lie, and this is the one row where the grant is askable
  /// in-app rather than a walk to a settings screen.
  Future<void> setShareVitals(bool value) async {
    if (value) {
      // Re-probe rather than trusting whatever the last [refresh] left
      // behind. That refresh is async and fired from initState, so a quick
      // tap can land while `vitalsAvailability` is still its initial
      // "unavailable" — and the old code answered that by returning
      // silently, which is indistinguishable from the button being broken.
      await _refreshVitals();
      if (vitalsUnavailable) return;
      if (!vitalsGranted) {
        final granted = await requestVitalsPermissions();
        if (!granted) return;
      }
    }
    shareVitals = value;
    await _onSetShareVitals(value);
    notifyListeners();
    await _refreshVitals();
  }

  /// Opens the permission flow, and — when that round-trip comes back with
  /// nothing granted — falls straight through to Health Connect's settings
  /// instead of leaving a button that appears to do nothing.
  ///
  /// That fallback is the fix for a real on-device failure: the request can
  /// come back false without ever showing the user anything (permissions
  /// already denied twice, so Android stops prompting; a ROM that doesn't
  /// surface the sheet). From the user's side the difference between "you
  /// said no" and "nothing happened" is invisible, so the recovery path is
  /// the same either way: put them where they CAN say yes, and say so.
  Future<bool> requestVitalsPermissions() async {
    if (!isSupported) return false;
    await _vitalsChannel.requestPermissions();
    // Trust the re-read, not the request's own answer — same reason the
    // native side re-queries: what's granted is Health Connect's fact.
    await _refreshVitals();
    if (vitalsGranted) return true;

    final opened = await _vitalsChannel.openSettings();
    vitalsMessage = opened
        ? AppStrings.vitalsGrantFallback
        : AppStrings.vitalsSettingsUnavailable;
    notifyListeners();
    return false;
  }

  /// The "open health connect ⚙︎" button. Used for the background-access
  /// warning as well as the grant fallback — same destination, and the
  /// screen calls [refresh] when the user comes back.
  Future<void> openVitalsSettings() async {
    if (!isSupported) return;
    final opened = await _vitalsChannel.openSettings();
    if (!opened) {
      vitalsMessage = AppStrings.vitalsSettingsUnavailable;
      notifyListeners();
    }
  }

  /// Test-only seam onto [_refreshVitals] — the production callers are
  /// [refresh] (which also probes half a dozen unrelated platform channels)
  /// and the grant flow.
  @visibleForTesting
  Future<void> refreshVitalsForTest() => _refreshVitals();

  /// Re-reads availability, both grants, and (only when reads are in place
  /// and the user has opted in) whether there's actually any data behind
  /// them. The data probe is deliberately skipped while the toggle is off:
  /// this row's preview is about the state of a feature that's ON, and
  /// reading someone's heart rate to decide what label to draw would be
  /// exactly the thing the opt-in exists to prevent.
  Future<void> _refreshVitals() async {
    if (!isSupported) return;
    vitalsAvailability = await _vitalsChannel.availability();
    final available = vitalsAvailability == VitalsAvailability.available;
    vitalsGranted = available && await _vitalsChannel.hasPermissions();
    vitalsBackgroundGranted =
        vitalsGranted && await _vitalsChannel.hasBackgroundPermission();
    if (shareVitals && vitalsGranted) {
      vitalsHasData = !(await _vitalsChannel.read()).isEmpty;
    } else {
      vitalsHasData = false;
    }
    // The grant-fallback line is about one failed attempt, not a lasting
    // state — once reads are granted it has nothing left to say. The
    // foreground-only warning replaces it, and clears itself the same way.
    if (vitalsGranted) {
      vitalsMessage = vitalsForegroundOnly
          ? AppStrings.vitalsForegroundOnly
          : null;
    }
    notifyListeners();
  }

  Future<void> _refreshActivityPreview() async {
    if (!isSupported) return;
    final package = await _presenceChannel.getForegroundAppPreview();
    final mapped = ActivityMapper.mapAndroidPackage(
      package,
      shareUnknown: shareUnknownApps,
    );
    final message = resolvePreviewMessage(
      shareFocusedApp: shareFocusedApp,
      hasUsageAccess: usageAccessGranted,
      hasReading: package != null,
      mappedLabel: mapped,
    );
    if (message == activityPreview) return;
    activityPreview = message;
    notifyListeners();
  }

  /// Pure resolution of the `shareFocusedApp` preview line from
  /// already-computed inputs — no platform channel, no I/O — so it's
  /// directly unit-testable against every state the toggle/grant/probe can
  /// be in. Mirrors `SharingSettingsViewModel.resolvePreviewMessage` on
  /// desktop, plus the one thing Android needs that desktop doesn't: the
  /// Usage Access grant, checked before the toggle even matters for
  /// reading (it gates the OS signal itself, not just our own opt-in).
  @visibleForTesting
  static String resolvePreviewMessage({
    required bool shareFocusedApp,
    required bool hasUsageAccess,
    required bool hasReading,
    required String? mappedLabel,
  }) {
    if (!shareFocusedApp) return AppStrings.sharingPreviewOff;
    if (!hasUsageAccess) return AppStrings.sharingPreviewGrantUsageAccess;
    if (!hasReading) return AppStrings.sharingPreviewNoReadingAndroid;
    if (mappedLabel == null) return AppStrings.sharingPreviewUnmapped;
    return AppStrings.sharingPreviewSharing(mappedLabel);
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
    if (value) await _restartServiceForLocation();
  }

  /// Android grants the `location` foreground-service type only when the
  /// service *starts* with the permission already held — a service that was
  /// already running when the grant happened keeps its old type set and
  /// background fixes stay blocked. So when location becomes usable (grant
  /// flipped, or sharing turned on), bounce the running service once.
  Future<void> _restartServiceForLocation() async {
    if (!serviceRunning || !locationWhileInUseGranted) return;
    await KehaiForegroundTask.stop();
    await KehaiForegroundTask.start();
    await refresh();
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

  @override
  void dispose() {
    _activityPreviewTimer?.cancel();
    _activityPreviewTimer = null;
    super.dispose();
  }
}
