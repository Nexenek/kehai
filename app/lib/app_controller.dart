import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import 'data/repositories/art_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/board_repository.dart';
import 'data/repositories/countdown_repository.dart';
import 'data/repositories/couple_repository.dart';
import 'data/repositories/device_repository.dart';
import 'data/repositories/doodle_repository.dart';
import 'data/repositories/shared_file_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/instant_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/pet_repository.dart';
import 'data/repositories/ping_repository.dart';
import 'data/repositories/question_repository.dart';
import 'data/repositories/status_repository.dart';
import 'data/repositories/touch_repository.dart';
import 'data/services/background/kehai_foreground_task.dart';
import 'data/services/background/location_publisher.dart';
import 'data/services/device_info_service.dart';
import 'data/services/heartbeat_service.dart';
import 'data/services/notifications/app_focus.dart';
import 'data/services/notifications/kehai_notifier.dart';
import 'data/services/notifications/notification_hub.dart';
import 'data/services/pocketbase_client.dart';
import 'data/services/presence/android/android_presence_service.dart';
import 'data/services/presence/android/vitals_service.dart';
import 'data/services/presence/linux_presence_service.dart';
import 'data/services/presence/presence_service.dart';
import 'data/services/presence/presence_service_factory.dart';
import 'data/services/presence/windows_presence_service.dart';
import 'data/services/prefs_service.dart';

/// Which screen the app should currently show. This is intentionally a
/// flat state machine rather than a router — the onboarding flow is
/// strictly linear and the whole app is one couple's home, so named routes
/// would add ceremony without buying anything.
enum AppStage { loading, serverSetup, auth, coupleSetup, home }

/// The composition root: owns the PocketBase client and every
/// repository/service built on top of it, and tracks which [AppStage] the
/// app is in. Plain [ChangeNotifier] per the "avoid heavyweight state
/// management" instruction — screens listen via [AppScope]/ListenableBuilder.
class AppController extends ChangeNotifier {
  AppController();

  late final PrefsService prefs;
  final DeviceInfoService deviceInfoService = const DeviceInfoService();

  /// Notifications (kb/roadmap.md's client-side notifications v1). Built in
  /// [init] once [prefs] exists, since the notifier reads the per-event
  /// sound choices straight out of it.
  late final KehaiNotifier notifier;
  late final KehaiNotifications notifications;

  /// "Is the user looking at Kehai on this device right now" — the
  /// foreground-suppression half of [decideNotification]. Registers its own
  /// window_manager listener rather than extending [DesktopWindowService],
  /// so the window service stays the sole owner of the window itself.
  final AppFocusTracker appFocus = AppFocusTracker();

  /// One presence source for the lifetime of the app — the heartbeat
  /// service just subscribes/unsubscribes to it across log-in/log-out
  /// rather than owning its lifecycle (see [HeartbeatService]'s doc
  /// comment on why it doesn't dispose the service it's given).
  final PresenceService presenceService = createPresenceService();

  /// The Health Connect half of this phone's telemetry (steps + heart
  /// rate). Like [presenceService] it lives for the whole app rather than
  /// per-connection, so the `shareVitals` toggle has one stable thing to
  /// push onto; a no-op off Android, where the channel simply isn't there.
  final VitalsService vitalsService = VitalsService();

  AppStage stage = AppStage.loading;
  String? connectionError;

  AuthRepository? authRepository;
  CoupleRepository? coupleRepository;
  StatusRepository? statusRepository;
  DeviceRepository? deviceRepository;
  CountdownRepository? countdownRepository;
  NoteRepository? noteRepository;
  DoodleRepository? doodleRepository;
  InstantRepository? instantRepository;
  LocationRepository? locationRepository;
  PetRepository? petRepository;
  PingRepository? pingRepository;
  TouchRepository? touchRepository;
  BoardRepository? boardRepository;
  QuestionRepository? questionRepository;
  ArtRepository? artRepository;
  SharedFileRepository? sharedFileRepository;
  EventRepository? eventRepository;
  HeartbeatService? heartbeatService;

  /// The app's own OwnTracks-compatible tracker (kb/contracts.md
  /// "Location"). Android-only — see [LocationPublisher]'s doc comment;
  /// null everywhere else, which every call site below already treats the
  /// same as "not running".
  LocationPublisher? locationPublisher;

  /// Whether *this* (UI) isolate currently owns presence/location duty —
  /// mirrors [HomeViewModel]'s private `_ownsHeartbeat`, but has to live
  /// here because [handOffPresenceToBackground] (the one place the
  /// hand-off decision is made) is the only hook [HomeViewModel] calls.
  /// True until that decision runs, so nothing here fires early.
  bool _uiOwnsLocation = true;

  String get serverUrl => prefs.serverUrl ?? '';

  Future<void> init() async {
    prefs = await PrefsService.create();
    notifier = KehaiNotifier(prefs: prefs);
    notifications = KehaiNotifications(notifier: notifier, focus: appFocus);
    unawaited(notifier.initialize());
    // Android's notifications are raised by the background isolate whenever
    // it's up (see [handOffPresenceToBackground]); it learns the app's
    // foreground state from here, because it has no window of its own to
    // watch. Desktop needs no push — the tracker and the notifier live in
    // the same isolate there.
    appFocus.onChanged = (foreground) {
      if (KehaiForegroundTask.isSupported) {
        KehaiForegroundTask.notifyAppForeground(foreground);
      }
    };
    appFocus.start();
    _applyActivitySharingPrefs();
    final savedUrl = prefs.serverUrl;
    if (savedUrl == null || savedUrl.isEmpty) {
      stage = AppStage.serverSetup;
      notifyListeners();
      return;
    }

    final ok = await _connect(savedUrl);
    if (!ok) {
      stage = AppStage.serverSetup;
      notifyListeners();
      return;
    }
    _resolveStageAfterConnect();
    notifyListeners();
  }

  /// Tries to reach [url]'s health endpoint without persisting anything —
  /// used by the "test connection" button.
  Future<bool> testConnection(String url) async {
    try {
      final pb = await PocketBaseClientFactory.create(_normalize(url));
      await pb.health.check();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Confirms [url] works, persists it, and moves on to auth/couple/home.
  Future<bool> confirmServer(String url) async {
    final normalized = _normalize(url);
    final ok = await _connect(normalized);
    if (!ok) {
      notifyListeners();
      return false;
    }
    await prefs.setServerUrl(normalized);
    _resolveStageAfterConnect();
    notifyListeners();
    return true;
  }

  Future<bool> _connect(String url) async {
    try {
      final pb = await PocketBaseClientFactory.create(url);
      await pb.health.check();
      authRepository = AuthRepository(pb);
      coupleRepository = CoupleRepository(pb, authRepository!);
      statusRepository = StatusRepository(pb);
      deviceRepository = DeviceRepository(pb);
      countdownRepository = CountdownRepository(pb);
      noteRepository = NoteRepository(pb);
      doodleRepository = DoodleRepository(pb);
      instantRepository = InstantRepository(pb);
      locationRepository = LocationRepository(pb, authRepository!);
      petRepository = PetRepository(pb);
      pingRepository = PingRepository(pb);
      touchRepository = TouchRepository(pb);
      boardRepository = BoardRepository(pb);
      questionRepository = QuestionRepository(pb);
      artRepository = ArtRepository(pb);
      sharedFileRepository = SharedFileRepository(pb);
      eventRepository = EventRepository(pb);
      heartbeatService = HeartbeatService(
        deviceRepository!,
        deviceInfoService,
        presenceService: presenceService,
        // Android only in practice — [VitalsService] short-circuits to null
        // everywhere else, so this costs desktop nothing. It matters
        // pre-hand-off (and whenever the hand-off fails): the UI isolate is
        // the heartbeat writer then, so it has to carry vitals too.
        extraTelemetry: vitalsService.telemetry,
      );
      // Desktop location is out of scope for now (geolocator_linux/windows
      // exist but nothing consumes them yet) — only build the publisher on
      // Android, so every other platform's `locationPublisher` stays null
      // and every call below is naturally a no-op.
      locationPublisher = Platform.isAndroid
          ? LocationPublisher(
              pb: pb,
              batteryLevel: () => presenceService.current.battery,
            )
          : null;
      connectionError = null;
      return true;
    } catch (_) {
      connectionError =
          "couldn't reach your server (・_・;) — check the address or Tailscale?";
      return false;
    }
  }

  void _resolveStageAfterConnect() {
    final auth = authRepository!;
    if (!auth.isLoggedIn) {
      stage = AppStage.auth;
      return;
    }
    stage = auth.coupleId == null ? AppStage.coupleSetup : AppStage.home;
  }

  /// The `shareFocusedApp`/`shareUnknownApps` opt-ins (kb/features.md
  /// "Focused-app status"), read straight from [prefs] so the desktop
  /// sharing-settings window and the Android phone-superpowers screen
  /// always show the persisted value rather than a copy that could drift.
  bool get shareFocusedApp => prefs.shareFocusedApp;
  bool get shareUnknownApps => prefs.shareUnknownApps;

  /// Persists the toggle and pushes it straight into the live
  /// [presenceService] so the very next poll honours it — no restart
  /// needed, and turning it off means the next poll (Windows) or the
  /// native poll loop (Android) genuinely stops looking rather than just
  /// discarding what it already read. Also nudges the background isolate
  /// (if it's the one currently holding presence duty) so it doesn't have
  /// to wait for its own 60s tick to notice — see
  /// [KehaiForegroundTask.notifyPrefsChanged].
  Future<void> setShareFocusedApp(bool value) async {
    await prefs.setShareFocusedApp(value);
    _applyActivitySharingPrefs();
    KehaiForegroundTask.notifyPrefsChanged();
    notifyListeners();
  }

  Future<void> setShareUnknownApps(bool value) async {
    await prefs.setShareUnknownApps(value);
    _applyActivitySharingPrefs();
    KehaiForegroundTask.notifyPrefsChanged();
    notifyListeners();
  }

  /// Pushes the persisted opt-ins onto whichever concrete [presenceService]
  /// this platform has — a no-op on the stub (nothing to wire there) — plus
  /// `shareVitals` onto [vitalsService], which every platform has (it just
  /// answers nothing off Android).
  void _applyActivitySharingPrefs() {
    vitalsService.enabled = prefs.shareVitals;
    final service = presenceService;
    if (service is WindowsPresenceService) {
      service.shareFocusedApp = prefs.shareFocusedApp;
      service.shareUnknownApps = prefs.shareUnknownApps;
    } else if (service is AndroidPresenceService) {
      service.shareFocusedApp = prefs.shareFocusedApp;
      service.shareUnknownApps = prefs.shareUnknownApps;
    } else if (service is LinuxPresenceService) {
      service.shareFocusedApp = prefs.shareFocusedApp;
      service.shareUnknownApps = prefs.shareUnknownApps;
    }
  }

  /// Called after a successful login/register.
  void onAuthenticated() {
    final coupleId = authRepository?.coupleId;
    stage = coupleId == null ? AppStage.coupleSetup : AppStage.home;
    notifyListeners();
  }

  /// Called after creating/joining a couple.
  void onCoupleReady() {
    stage = AppStage.home;
    notifyListeners();
  }

  /// Android: hands presence duty to the foreground service's background
  /// isolate, which keeps heartbeating and refreshing the partner
  /// notification once the app is off screen. Returns true if the service
  /// is up — in which case the UI isolate must NOT also heartbeat, or the
  /// same device row gets written twice every 30s.
  ///
  /// Returns false on desktop, and on Android whenever the service can't
  /// start (notification permission denied, OEM restriction); the caller
  /// then falls back to the phase-2a behaviour of heartbeating from the UI
  /// isolate while the app is open.
  Future<bool> handOffPresenceToBackground() async {
    if (!KehaiForegroundTask.isSupported) return false;

    // The service can run without POST_NOTIFICATIONS, but its notification
    // — which IS the partner window — would be invisible. Ask once, the
    // first time we get here; never again, since Android permanently mutes
    // the prompt after two denials and the superpowers screen is the
    // user-initiated route from then on.
    if (!prefs.askedNotificationPermission &&
        !await KehaiForegroundTask.hasNotificationPermission) {
      await prefs.markAskedNotificationPermission();
      await KehaiForegroundTask.requestNotificationPermission();
    }

    final handedOff = await KehaiForegroundTask.start();
    // Same single-writer rule as the heartbeat/device row: only whichever
    // isolate actually won presence duty runs the location publisher. When
    // the background service took it, KehaiTaskHandler re-applies
    // `shareLocation` on its own tick instead (kb/platform-android.md).
    _uiOwnsLocation = !handedOff;
    if (_uiOwnsLocation) {
      unawaited(locationPublisher?.setEnabled(prefs.shareLocation));
    }
    // Same single-writer rule the heartbeat and the location publisher
    // follow, applied to notifications: whichever isolate owns the realtime
    // subscriptions is the one allowed to notify. When the service took
    // over it subscribes to pings/doodles/instants/answers itself (see
    // [KehaiTaskHandler]) and keeps doing so with the app closed — so the
    // UI isolate's view models must go quiet, or every ping would arrive
    // twice. When the hand-off failed (permission denied, OEM restriction)
    // the UI isolate stays the notifier, exactly like it stays the
    // heartbeat.
    notifications.enabled = !handedOff;
    // The service starts life not knowing whether the app is on screen; it
    // very much is, at this exact moment.
    if (handedOff) {
      KehaiForegroundTask.notifyAppForeground(appFocus.isForeground.value);
    }
    return handedOff;
  }

  /// The "share my location" opt-in (kb/contracts.md "Location"). Read
  /// straight from [prefs] like [shareFocusedApp] above, so the superpowers
  /// screen always shows the persisted value.
  bool get shareLocation => prefs.shareLocation;

  /// Persists the toggle and, if this isolate is the one currently doing
  /// presence duty, applies it to the live [locationPublisher] immediately
  /// — no restart needed. When the background service owns presence
  /// instead, [KehaiForegroundTask.notifyPrefsChanged] nudges it to pick
  /// the new value up right away rather than waiting for its next tick
  /// (see [KehaiTaskHandler.onReceiveData]) — that tick remains the
  /// fallback if the nudge itself doesn't land.
  Future<void> setShareLocation(bool value) async {
    await prefs.setShareLocation(value);
    if (_uiOwnsLocation) {
      await locationPublisher?.setEnabled(value);
    } else {
      KehaiForegroundTask.notifyPrefsChanged();
    }
    notifyListeners();
  }

  /// The "share heartbeat & steps ♥︎" opt-in (kb/platform-android.md
  /// "Steps / heart rate"). Read straight from [prefs] like the toggles
  /// above, so the superpowers screen always shows the persisted value.
  bool get shareVitals => prefs.shareVitals;

  /// Persists the toggle, applies it to this isolate's [vitalsService], and
  /// nudges the background isolate — the same belt-and-braces pair
  /// [setShareFocusedApp] uses, and for the same reason: exactly one of the
  /// two isolates is heartbeating at any moment, and which one it is
  /// depends on whether the hand-off succeeded. Doing both is cheap
  /// (`notifyPrefsChanged` is a no-op off Android and when no service is
  /// running) and means neither path can go stale.
  Future<void> setShareVitals(bool value) async {
    await prefs.setShareVitals(value);
    vitalsService.enabled = value;
    KehaiForegroundTask.notifyPrefsChanged();
    notifyListeners();
  }

  void logOut() {
    heartbeatService?.stop();
    locationPublisher?.stop();
    // The background isolate holds this user's session; stop it before the
    // token goes away rather than leaving a notification about a partner
    // we're no longer logged in to see.
    unawaited(KehaiForegroundTask.stop());
    authRepository?.logout();
    stage = AppStage.auth;
    notifyListeners();
  }

  String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

/// Makes the [AppController] reachable from any widget below it via
/// `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.of() called with no AppScope ancestor');
    return scope!.notifier!;
  }
}
