import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/countdown_repository.dart';
import 'data/repositories/couple_repository.dart';
import 'data/repositories/device_repository.dart';
import 'data/repositories/doodle_repository.dart';
import 'data/repositories/instant_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/status_repository.dart';
import 'data/services/background/kehai_foreground_task.dart';
import 'data/services/device_info_service.dart';
import 'data/services/heartbeat_service.dart';
import 'data/services/pocketbase_client.dart';
import 'data/services/presence/android/android_presence_service.dart';
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

  /// One presence source for the lifetime of the app — the heartbeat
  /// service just subscribes/unsubscribes to it across log-in/log-out
  /// rather than owning its lifecycle (see [HeartbeatService]'s doc
  /// comment on why it doesn't dispose the service it's given).
  final PresenceService presenceService = createPresenceService();

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
  HeartbeatService? heartbeatService;

  String get serverUrl => prefs.serverUrl ?? '';

  Future<void> init() async {
    prefs = await PrefsService.create();
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
      heartbeatService = HeartbeatService(
        deviceRepository!,
        deviceInfoService,
        presenceService: presenceService,
      );
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
  /// discarding what it already read.
  Future<void> setShareFocusedApp(bool value) async {
    await prefs.setShareFocusedApp(value);
    _applyActivitySharingPrefs();
    notifyListeners();
  }

  Future<void> setShareUnknownApps(bool value) async {
    await prefs.setShareUnknownApps(value);
    _applyActivitySharingPrefs();
    notifyListeners();
  }

  /// Pushes the persisted opt-ins onto whichever concrete [presenceService]
  /// this platform has — a no-op on the stub (nothing to wire there).
  void _applyActivitySharingPrefs() {
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

    return KehaiForegroundTask.start();
  }

  void logOut() {
    heartbeatService?.stop();
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
