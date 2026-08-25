import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

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
import 'data/repositories/mood_jar_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/pet_repository.dart';
import 'data/repositories/ping_repository.dart';
import 'data/repositories/portal_signal_repository.dart';
import 'data/repositories/question_repository.dart';
import 'data/repositories/status_repository.dart';
import 'data/repositories/touch_repository.dart';
import 'data/repositories/turn_repository.dart';
import 'data/services/background/kehai_foreground_task.dart';
import 'data/services/background/location_publisher.dart';
import 'data/services/connectivity_monitor.dart';
import 'data/services/device_info_service.dart';
import 'data/services/heartbeat_service.dart';
import 'data/services/notifications/app_focus.dart';
import 'data/services/notifications/kehai_notifier.dart';
import 'data/services/notifications/notification_hub.dart';
import 'data/services/pocketbase_client.dart';
import 'data/services/portal/portal_engine.dart';
import 'data/services/presence/android/android_presence_service.dart';
import 'data/services/presence/android/vitals_service.dart';
import 'data/services/presence/linux_presence_service.dart';
import 'data/services/presence/presence_service.dart';
import 'data/services/presence/presence_service_factory.dart';
import 'data/services/presence/windows_presence_service.dart';
import 'data/services/prefs_service.dart';
import 'ui/core/strings/app_strings.dart';

/// Which screen the app should currently show. This is intentionally a
/// flat state machine rather than a router — the onboarding flow is
/// strictly linear and the whole app is one couple's home, so named routes
/// would add ceremony without buying anything.
enum AppStage { loading, serverSetup, auth, coupleSetup, home }

/// How long a *gating* health check gets before it counts as a failure —
/// the ones a person is waiting on ("test connection", "continue"). A
/// server that has gone away rarely refuses the connection; it just never
/// answers, and without this the loading screen would sit there for the
/// whole of the platform's default socket timeout.
const _healthCheckTimeout = Duration(seconds: 5);

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

  /// The client every repository below is built on, kept so the
  /// connectivity monitor has something to knock on without rebuilding
  /// anything. Null until [_buildStack] has run once.
  PocketBase? _pb;

  ConnectivityMonitor? _connectivity;
  bool _online = true;

  /// Whether the server answered the last time we asked (see
  /// [ConnectivityMonitor]). Optimistically true until the first probe
  /// comes back, so a healthy launch never flashes an offline badge.
  ///
  /// Nothing in the app *waits* on this — the stack is built and the stage
  /// resolved whether or not the server is reachable. It exists so the home
  /// screen can say so quietly, and so the once-only things (the portal
  /// subscription, the heartbeat) get a nudge the moment it flips back.
  bool get online => _online;

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
  MoodJarRepository? moodJarRepository;
  PortalSignalRepository? portalSignalRepository;
  TurnRepository? turnRepository;
  HeartbeatService? heartbeatService;

  PortalEngine? _portalEngine;

  /// Portal mode's engine — built and subscribed in [_connect], alongside
  /// every other repository, so a knock can arrive while the app sits on
  /// home (or anywhere else) rather than only while someone happens to have
  /// the curtain screen open. [PortalKnockBridge] is what actually does
  /// something with that: notify, and maybe auto-accept.
  ///
  /// Null until a portal-capable session exists (logged in, paired).
  PortalEngine? get portalEngine => _portalEngine;

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
      // Coming on screen is the one moment a Health Connect read is certain
      // to be allowed (without READ_HEALTH_DATA_IN_BACKGROUND every read
      // from a backgrounded process is refused), so spend it: drop the
      // cached reading and beat. Only when THIS isolate is the heartbeat
      // writer — when the service took over it does the same thing in
      // [KehaiTaskHandler.onReceiveData], and both doing it would write the
      // same device row twice.
      if (foreground && _uiOwnsLocation) {
        vitalsService.invalidateCache();
        unawaited(heartbeatService?.pingNow() ?? Future<void>.value());
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

    // Startup is never gated on reachability. Kehai autostarts at login and
    // the server is somebody's home machine over a tailnet, so "the network
    // isn't up yet" is the *normal* first few seconds of a session — and
    // answering it by dropping the user onto the server-setup screen (with
    // an empty address field, no less) threw away a saved URL and a saved
    // session for a condition that fixes itself.
    //
    // Everything [_buildStack] does is local construction: a [PocketBase]
    // object, repositories around it, and a stage decision that reads
    // [AuthRepository.isLoggedIn]/[AuthRepository.coupleId] — both of which
    // come from the [AsyncAuthStore] seeded from shared_preferences in
    // [PocketBaseClientFactory.create], never from the network. So build it
    // all, land on the right screen, and let [ConnectivityMonitor] discover
    // the server whenever it turns up.
    try {
      await _buildStack(savedUrl);
    } catch (_) {
      // Not a reachability failure — the only way to land here is a client
      // that couldn't be constructed at all — and there is nothing to show
      // for that but the setup screen.
      connectionError = AppStrings.connectionFailed;
      stage = AppStage.serverSetup;
      notifyListeners();
      return;
    }
    _resolveStageAfterConnect();
    _startConnectivityMonitor();
    notifyListeners();
  }

  /// Tries to reach [url]'s health endpoint without persisting anything —
  /// used by the "test connection" button.
  Future<bool> testConnection(String url) async =>
      await _resolveReachable(url) != null;

  /// The candidate URLs a typed address expands to, in the order they're
  /// tried. A bare `kehai.tail1234.ts.net` (no scheme — the most common
  /// way people type an address, found on-device) is tried as https first
  /// (a Tailscale-Serve or Caddy setup) and plain http second (the base
  /// stack, e.g. `100.x.x.x:8090`). An address that already carries a
  /// scheme is taken literally.
  @visibleForTesting
  static List<String> serverCandidates(String url) {
    final u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isEmpty) return const [];
    if (u.contains('://')) return [u];
    return ['https://$u', 'http://$u'];
  }

  Future<String?> _resolveReachable(String url) async {
    for (final candidate in serverCandidates(url)) {
      try {
        final pb = await PocketBaseClientFactory.create(candidate);
        // Capped: somebody is watching a spinner while this runs, and an
        // https guess against a plain-http server is exactly the case that
        // hangs rather than refusing.
        await pb.health.check().timeout(_healthCheckTimeout);
        return candidate;
      } catch (_) {
        // Try the next scheme.
      }
    }
    return null;
  }

  /// Confirms [url] works, persists it, and moves on to auth/couple/home.
  Future<bool> confirmServer(String url) async {
    // Same scheme-guessing as the test button, so what gets persisted is
    // the candidate that actually answered — never the bare hostname.
    final normalized = await _resolveReachable(url) ?? _normalize(url);
    final ok = await _connect(normalized);
    if (!ok) {
      notifyListeners();
      return false;
    }
    await prefs.setServerUrl(normalized);
    _resolveStageAfterConnect();
    // We just health-checked this address twice over; there is nothing left
    // to discover. Restart the monitor rather than reuse it — the client it
    // was knocking on has been replaced.
    _online = true;
    _startConnectivityMonitor();
    notifyListeners();
    return true;
  }

  /// (Re)starts the "can we see the server" loop against the current
  /// client. Always replaces whatever was running, so there is never more
  /// than one loop and never one still knocking on a retired client.
  void _startConnectivityMonitor() {
    _connectivity?.dispose();
    _connectivity = ConnectivityMonitor(
      probe: () async {
        final pb = _pb;
        if (pb == null) throw StateError('no client to probe');
        await pb.health.check();
      },
      onChanged: _onConnectivityChanged,
      online: _online,
    )..start();
  }

  /// The server came back (or went away). Going away needs nothing but the
  /// repaint — every request already fails on its own, and the realtime
  /// socket is busy reconnecting itself (see [_buildStack]).
  ///
  /// Coming back needs the two things that only ever happen once:
  /// [PortalEngine.init]'s subscription (idempotent, and a no-op if the
  /// in-flight one is still waiting for a socket) and a heartbeat, so the
  /// partner sees this device light up now rather than up to 30s from now.
  ///
  /// The beat obeys the same single-writer rule as everything else that
  /// touches the device row (see [appFocus]'s handler and
  /// [handOffPresenceToBackground]): only when THIS isolate is the
  /// heartbeat writer. When the Android service took over, it has its own
  /// tick and its own client, and two writers means the row gets written
  /// twice.
  void _onConnectivityChanged(bool online) {
    _online = online;
    if (online) {
      _startPortalEngineIfReady();
      if (_uiOwnsLocation) {
        unawaited(heartbeatService?.pingNow() ?? Future<void>.value());
      }
    }
    notifyListeners();
  }

  /// The explicit-entry path: prove [url] answers *before* touching the
  /// live stack, then build on it. Only [confirmServer] — somebody typing
  /// an address and pressing continue — comes through here; [init]
  /// deliberately doesn't (see its note). The check-first order matters
  /// here too: a typo'd address entered from settings must not tear down
  /// the repositories (and the portal engine, and its camera) that the
  /// session is still using.
  Future<bool> _connect(String url) async {
    try {
      final probe = await PocketBaseClientFactory.create(url);
      await probe.health.check().timeout(_healthCheckTimeout);
    } catch (_) {
      connectionError = AppStrings.connectionFailed;
      return false;
    }
    try {
      await _buildStack(url);
      return true;
    } catch (_) {
      connectionError = AppStrings.connectionFailed;
      return false;
    }
  }

  /// Builds the client and everything hanging off it. Purely local — not
  /// one line of this asks the server anything, which is exactly what lets
  /// [init] run it while the server is still unreachable.
  ///
  /// The realtime subscriptions started from here are fine offline too: the
  /// pocketbase SDK's [SseClient] reconnects on its own, forever, with a
  /// stepped backoff, and [RealtimeService] re-submits the whole
  /// subscription list on every (re)connect. A `subscribe` issued with no
  /// server simply doesn't complete until one appears — it does not fail
  /// permanently — so nothing here needs re-establishing by hand when the
  /// network comes back.
  Future<void> _buildStack(String url) async {
    final pb = await PocketBaseClientFactory.create(url);
    _pb = pb;
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
    moodJarRepository = MoodJarRepository(pb);
    portalSignalRepository = PortalSignalRepository(pb);
    turnRepository = TurnRepository(pb);
    // A reconnect builds fresh repositories, so an engine holding the old
    // ones has to go — and it must go the safe way, which is the one that
    // releases the camera.
    _disposePortalEngine();
    _portalEngine = PortalEngine(
      auth: authRepository!,
      signals: portalSignalRepository!,
      turn: turnRepository!,
    );
    // Not subscribed yet — see [_startPortalEngineIfReady]'s doc. This is
    // the same "isLoggedIn gate" [KehaiTaskHandler._connect] uses before
    // it subscribes to anything: a knock subscription opened while the
    // client has no session yet is a socket for nothing.
    _startPortalEngineIfReady();
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
  }

  /// Where a built stack lands: auth, couple setup, or home. Reads nothing
  /// but the local auth store ([AuthRepository.isLoggedIn] is
  /// `authStore.isValid`, [AuthRepository.coupleId] a field off the record
  /// that store was seeded with), so it answers just as correctly with no
  /// server in sight — which is what lets [init] call it unconditionally.
  void _resolveStageAfterConnect() {
    final auth = authRepository!;
    if (!auth.isLoggedIn) {
      stage = AppStage.auth;
      return;
    }
    stage = auth.coupleId == null ? AppStage.coupleSetup : AppStage.home;
    _startPortalEngineIfReady();
  }

  /// Subscribes the portal engine, once — the same "built at connect time,
  /// subscribed only once logged in" split [KehaiTaskHandler] follows,
  /// so a knock can arrive while the app sits anywhere past onboarding
  /// (home, calendar, wherever), not only while the curtain happens to be
  /// open. [PortalEngine.init] is idempotent, so calling this from every
  /// place login state can become true — right after connecting (an
  /// already-logged-in session), and after [onAuthenticated]/
  /// [onCoupleReady] (a session that just became one) — costs nothing extra
  /// on whichever paths turn out not to be the one that mattered.
  void _startPortalEngineIfReady() {
    if (authRepository?.isLoggedIn != true) return;
    unawaited(_portalEngine?.init());
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
    _startPortalEngineIfReady();
    notifyListeners();
  }

  /// Called after creating/joining a couple.
  void onCoupleReady() {
    stage = AppStage.home;
    _startPortalEngineIfReady();
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
    // Before the token goes away, and unconditionally: [PortalEngine.dispose]
    // is the path that stops every capture track. Logging out with a live
    // portal must not leave a camera on.
    _disposePortalEngine();
    // The background isolate holds this user's session; stop it before the
    // token goes away rather than leaving a notification about a partner
    // we're no longer logged in to see.
    unawaited(KehaiForegroundTask.stop());
    authRepository?.logout();
    stage = AppStage.auth;
    notifyListeners();
  }

  /// The controller outlives every screen and is normally only let go of
  /// when the process is, but the connectivity loop is a repeating timer —
  /// it has to be cancelled here, or a test that builds a controller leaves
  /// one ticking.
  @override
  void dispose() {
    _connectivity?.dispose();
    _connectivity = null;
    _disposePortalEngine();
    super.dispose();
  }

  void _disposePortalEngine() {
    final engine = _portalEngine;
    _portalEngine = null;
    engine?.dispose();
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
