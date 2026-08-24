import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../domain/models/ambient_line.dart';
import '../../../domain/models/device_status.dart';
import '../../../domain/models/partner_status.dart';
import '../../../domain/notification_icon.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/couple_repository.dart';
import '../../repositories/device_repository.dart';
import '../../repositories/doodle_repository.dart';
import '../../repositories/instant_repository.dart';
import '../../repositories/ping_repository.dart';
import '../../repositories/question_repository.dart';
import '../../repositories/status_repository.dart';
import '../device_info_service.dart';
import '../heartbeat_service.dart';
import '../notifications/kehai_notifier.dart';
import '../notifications/notification_hub.dart';
import '../pocketbase_client.dart';
import '../prefs_service.dart';
import '../presence/android/android_presence_service.dart';
import '../presence/android/vitals_service.dart';
import '../presence/presence_service.dart';
import '../presence/presence_service_factory.dart';
import 'kehai_foreground_task.dart';
import 'location_publisher.dart';
import 'partner_notification.dart';
import 'partner_widget.dart';

/// The foreground service's Dart entry point. `@pragma('vm:entry-point')`
/// is load-bearing: the Kotlin side looks this function up by callback
/// handle and runs it in a *second* Flutter engine, so tree-shaking must
/// not touch it.
@pragma('vm:entry-point')
void kehaiTaskCallback() {
  FlutterForegroundTask.setTaskHandler(KehaiTaskHandler());
}

/// Everything Kehai needs to keep being a presence while the app isn't on
/// screen, running in the foreground service's background isolate:
///
/// 1. rebuilds the PocketBase client from the same SharedPreferences the
///    UI isolate persists server URL + auth token into,
/// 2. runs the same [HeartbeatService] + [PresenceService] pair the UI
///    isolate runs (battery, charging, screen-derived idle, now-playing),
/// 3. subscribes to the partner's `statuses` + `devices` records,
/// 4. pushes rendered notification strings down to the service,
/// 5. subscribes to `pings`, `doodles`, `instants` and `answers` and raises
///    a real local notification for each partner-authored event — the
///    Android half of kb/roadmap.md's client-side notifications, and the
///    reason a ping reaches the phone with Kehai closed and no push service
///    anywhere in the picture, and
/// 6. — when `shareLocation` is on — runs [LocationPublisher], the app's
///    own OwnTracks-compatible tracker (kb/contracts.md "Location"), and
///    keeps [PresenceService]'s `shareFocusedApp`/`shareUnknownApps`
///    opt-ins (kb/features.md "Focused-app status") and [VitalsService]'s
///    `shareVitals` opt-in (kb/platform-android.md "Steps / heart rate")
///    in sync too — see [_applySharingPrefs].
///
/// Note the deliberate asymmetry: this isolate *computes* every string
/// (mood kaomoji, ambient-line precedence, device indicator) and Kotlin
/// only renders them, so `resolveAmbientLine` has exactly one
/// implementation in the codebase.
///
/// ON-DEVICE VERIFICATION NEEDED: none of this can run in CI or on the dev
/// box — it needs a real Android device to confirm the second engine gets
/// its plugins registered (see `KehaiApplication.kt`), that PocketBase
/// realtime survives Doze, and that the notification updates as expected.
///
/// On the plugin question specifically, for the notifications added in this
/// wave: `flutter_local_notifications` is a normal pub plugin, and
/// flutter_foreground_task builds its engine with the plain
/// `FlutterEngine(context)` constructor — which defaults
/// `automaticallyRegisterPlugins` to true and so runs
/// `GeneratedPluginRegistrant` (verified by reading both
/// `ForegroundTask.kt` and the embedding's `FlutterEngine.java`, not
/// assumed). `KehaiApplication`'s lifecycle-listener hook is therefore only
/// needed for our own app-module plugin, and stays as it was.
class KehaiTaskHandler extends TaskHandler {
  PocketBase? _pb;
  CoupleRepository? _coupleRepository;
  StatusRepository? _statusRepository;
  DeviceRepository? _deviceRepository;
  PingRepository? _pingRepository;
  DoodleRepository? _doodleRepository;
  InstantRepository? _instantRepository;
  QuestionRepository? _questionRepository;
  HeartbeatService? _heartbeatService;
  PresenceService? _presenceService;
  VitalsService? _vitalsService;
  LocationPublisher? _locationPublisher;
  KehaiNotifier? _notifier;
  KehaiNotifications? _notifications;

  UnsubscribeFunc? _statusUnsub;
  UnsubscribeFunc? _deviceUnsub;
  UnsubscribeFunc? _pingUnsub;
  UnsubscribeFunc? _doodleUnsub;
  UnsubscribeFunc? _instantUnsub;
  UnsubscribeFunc? _answerUnsub;

  String? _partnerName;
  String? _partnerId;
  String? _myId;
  PartnerStatus? _partnerStatus;
  List<DeviceStatus> _partnerDevices = const [];
  PartnerNotificationContent? _lastRendered;

  /// The status-bar icon key last actually pushed to the notification —
  /// see [_render]'s doc comment on why this is tracked separately from
  /// [_lastRendered] (title/text) instead of folded into it.
  String? _lastIconKey;

  /// Whether today's daily question was already revealed the last time we
  /// looked. Only the *transition* to revealed is worth a notification — a
  /// re-check that finds it still open must stay quiet, and PocketBase
  /// delivers an `answers` event for our own answer too.
  bool _revealedToday = false;
  DateTime? _revealCheckedOn;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // A background engine starts bare: bind the framework, then run the
    // Dart-side plugin registrants so shared_preferences (and with it the
    // PocketBase auth store) actually resolves in this isolate.
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    KehaiForegroundTask.configure();

    await _render();

    try {
      await _connect();
    } catch (_) {
      // No server saved yet, no session, or the tailnet is down. The
      // service stays up with its "looking for your person" notification
      // and the next onRepeatEvent retries.
      return;
    }
  }

  Future<void> _connect() async {
    if (_pb != null) {
      // Already connected — still worth re-applying the sharing prefs every
      // tick, since this is the only isolate-side hook a toggle flipped
      // from the superpowers/sharing-settings screens while this service
      // owns presence has to reach the location publisher and presence
      // service (see `AppController.setShareLocation`/`setShareFocusedApp`
      // doc comments on the UI-isolate half of this).
      await _applySharingPrefs();
      return;
    }

    final prefs = await PrefsService.create();
    final serverUrl = prefs.serverUrl;
    if (serverUrl == null || serverUrl.isEmpty) return;

    final pb = await PocketBaseClientFactory.create(serverUrl);
    final auth = AuthRepository(pb);
    if (!auth.isLoggedIn) return;

    _pb = pb;
    _myId = auth.currentUserId;
    _coupleRepository = CoupleRepository(pb, auth);
    _statusRepository = StatusRepository(pb);
    _deviceRepository = DeviceRepository(pb);
    _pingRepository = PingRepository(pb);
    _doodleRepository = DoodleRepository(pb);
    _instantRepository = InstantRepository(pb);
    _questionRepository = QuestionRepository(pb);

    // The notifier lives in THIS isolate: a plugin instance never crosses an
    // isolate boundary, and neither does SharedPreferences' cache — which is
    // why [_applySharingPrefs] reloads and why `refreshFromPrefs` below
    // exists. `focus` is null here because this isolate has no window; the
    // app's foreground state arrives from the UI isolate over
    // `sendDataToTask` instead (see [onReceiveData]).
    final notifier = _notifier = KehaiNotifier(prefs: prefs);
    await notifier.initialize();
    _notifications = KehaiNotifications(notifier: notifier)
      ..myUserId = _myId ?? ''
      // Nothing is on screen at the moment the service starts — if the app
      // is open, the UI isolate corrects this immediately.
      ..foregroundOverride = false;

    final presence = createPresenceService();
    _presenceService = presence;
    // Vitals ride the existing heartbeat rather than getting a publisher of
    // their own — steps and heart rate are `devices` telemetry like battery
    // or now-playing, and this isolate is the single writer of that row
    // whenever it's up. `enabled` is set by [_applySharingPrefs] below.
    final vitals = _vitalsService = VitalsService();
    _heartbeatService = HeartbeatService(
      _deviceRepository!,
      const DeviceInfoService(),
      presenceService: presence,
      extraTelemetry: vitals.telemetry,
    )..start();

    // Same single-writer rule as the heartbeat above: this background
    // isolate only exists while it owns presence duty, so it's always safe
    // for it to run the location publisher too — see
    // `AppController.locationPublisher`'s doc comment for the UI-isolate
    // half of the hand-off.
    _locationPublisher = LocationPublisher(
      pb: pb,
      batteryLevel: () => presence.current.battery,
    );
    await _applySharingPrefs(prefs);

    await _refreshPartner();
    await _subscribe();
    await _render();
  }

  /// Re-reads every sharing toggle (`shareLocation`, `shareFocusedApp`,
  /// `shareUnknownApps`, `shareVitals`) and pushes each onto whichever live service
  /// actually owns it — cheap (SharedPreferences' instance is cached) and
  /// safe to call every tick, which is exactly what [onRepeatEvent] does,
  /// plus once immediately whenever [onReceiveData] hears from the UI
  /// isolate. `flutter_foreground_task`'s `sendDataToTask` gives an instant
  /// path for the latter (see [onReceiveData]); the 60s tick remains the
  /// fallback for whatever that missed — e.g. a toggle flipped before this
  /// isolate ever connected.
  ///
  /// This is the fix for a bug that shipped once already
  /// (kb/features.md "Focused-app status"): `shareFocusedApp`/
  /// `shareUnknownApps` toggled from the superpowers screen never reached
  /// this isolate at all, so the background service kept sharing (or not
  /// sharing) whatever the toggle said at the moment it last connected —
  /// exactly the stale-forever bug `shareLocation` had before it grew this
  /// same re-apply.
  Future<void> _applySharingPrefs([PrefsService? loaded]) async {
    final prefs = loaded ?? await PrefsService.create();
    // SharedPreferences caches per isolate: without this reload the UI
    // isolate's toggle writes are invisible here and the publisher/presence
    // service would stay stuck on whatever they saw at connect time.
    await prefs.reload();
    await _locationPublisher?.setEnabled(prefs.shareLocation);

    final presence = _presenceService;
    if (presence is AndroidPresenceService) {
      presence.shareFocusedApp = prefs.shareFocusedApp;
      presence.shareUnknownApps = prefs.shareUnknownApps;
    }

    // `shareVitals` (kb/platform-android.md "Steps / heart rate") gets the
    // same treatment for the same reason: flipped from the superpowers
    // screen in the UI isolate, but it's THIS isolate that does the Health
    // Connect reads once the app is backgrounded.
    _vitalsService?.enabled = prefs.shareVitals;

    // Sound choices are prefs too, and go stale here for exactly the same
    // reason. A sound picked in the app has to reach the channel this
    // isolate posts on, or the phone keeps playing the old one forever.
    await _notifier?.refreshFromPrefs();
  }

  /// `FlutterForegroundTask.sendDataToTask` lands here. Two payloads:
  ///
  /// - `app_foreground:0|1` — the app went off/on screen. This isolate
  ///   raises the notifications on Android, and has no window of its own to
  ///   watch, so this is how it knows whether the person is already looking
  ///   ([decideNotification]'s rule 2). The transition TO foreground does
  ///   double duty as the vitals refresh trigger — see [_onAppForeground].
  /// - anything else — the prefs nudge [KehaiForegroundTask.notifyPrefsChanged]
  ///   sends when a sharing toggle or a sound is changed in the app. Its
  ///   content carries nothing worth reading; receipt means "go re-read
  ///   prefs".
  @override
  void onReceiveData(Object data) {
    if (data is String &&
        data.startsWith(KehaiForegroundTask.foregroundSignalPrefix)) {
      final foreground = data.endsWith('1');
      _notifications?.foregroundOverride = foreground;
      if (foreground) _onAppForeground();
      return;
    }
    unawaited(_applySharingPrefs());
  }

  /// The app just came on screen. Health Connect only lets this isolate read
  /// vitals in the background when READ_HEALTH_DATA_IN_BACKGROUND is
  /// granted — and when it isn't, *this* is the one moment a read is
  /// guaranteed to succeed. So drop the cached (probably all-null) reading
  /// and beat immediately, which pushes fresh steps/bpm to the partner just
  /// from opening the app.
  ///
  /// Cheap enough to do unconditionally: with the grant in place it costs
  /// one extra read and one extra heartbeat per app open, and with the
  /// opt-in off [VitalsService.telemetry] short-circuits before touching
  /// the channel at all.
  void _onAppForeground() {
    _vitalsService?.invalidateCache();
    unawaited(_heartbeatService?.pingNow() ?? Future<void>.value());
  }

  /// Test-only hook for the foreground transition above — the real path
  /// arrives over `sendDataToTask`, which needs a live service.
  @visibleForTesting
  void appForegroundForTest() => _onAppForeground();

  /// Test-only hook: exercises the same prefs-reload-and-push path
  /// [_connect]/[onRepeatEvent]/[onReceiveData] all use, without spinning up
  /// PocketBase — see [presenceServiceForTest].
  @visibleForTesting
  Future<void> applySharingPrefsForTest(PrefsService prefs) =>
      _applySharingPrefs(prefs);

  /// Test-only seam: lets a unit test hand this handler a fake/real
  /// [PresenceService] (e.g. a bare [AndroidPresenceService]) without going
  /// through [_connect]'s real PocketBase/HeartbeatService wiring.
  @visibleForTesting
  set presenceServiceForTest(PresenceService? service) =>
      _presenceService = service;

  /// Same seam for the vitals half of [_applySharingPrefs] — a
  /// [VitalsService] built with a fake channel, so a test can assert the
  /// `shareVitals` toggle actually lands here.
  @visibleForTesting
  set vitalsServiceForTest(VitalsService? service) => _vitalsService = service;

  Future<void> _refreshPartner() async {
    final partner = await _coupleRepository?.fetchPartner();
    _partnerId = partner?.id;
    _partnerName = partner?.name;
    _notifications?.partnerName = partner?.name ?? '';
    if (partner == null) {
      _partnerStatus = null;
      _partnerDevices = const [];
      return;
    }
    _partnerStatus = await _statusRepository?.fetchStatus(partner.id);
    _partnerDevices =
        await _deviceRepository?.fetchDevicesForOwner(partner.id) ?? const [];
  }

  Future<void> _subscribe() async {
    _statusUnsub = await _statusRepository?.subscribe((status) {
      if (status.userId != _partnerId) return;
      _partnerStatus = status;
      unawaited(_render());
    });

    _deviceUnsub = await _deviceRepository?.subscribe((device) {
      if (device.ownerId != _partnerId) return;
      _partnerDevices = [
        ..._partnerDevices.where((d) => d.id != device.id),
        device,
      ];
      unawaited(_render());
    });

    await _subscribeNotifiables();
  }

  /// The four things worth interrupting someone for (see [KehaiEventKind] —
  /// and its note on why moods deliberately aren't among them).
  ///
  /// Every handler here does the same thing: pass the event to
  /// [KehaiNotifications], which applies the self-echo and foreground rules
  /// and then raises (or doesn't) the notification. None of them keep state
  /// — this isolate isn't rendering a feed, it's ringing a bell.
  Future<void> _subscribeNotifiables() async {
    final notifications = _notifications;
    if (notifications == null) return;

    _pingUnsub = await _pingRepository?.subscribe((ping) {
      notifications.report(
        () => notifications.reportPing(fromId: ping.fromId, kind: ping.kind),
      );
    });

    _doodleUnsub = await _doodleRepository?.subscribe((action, doodle) {
      // Doodles are immutable, so 'create' is the only action that means
      // "something arrived"; a 'delete' is the partner tidying up.
      if (action == 'delete') return;
      notifications.report(
        () => notifications.reportDoodle(authorId: doodle.authorId),
      );
    });

    _instantUnsub = await _instantRepository?.subscribe((action, instant) {
      if (action == 'delete') return;
      notifications.report(
        () => notifications.reportInstant(authorId: instant.authorId),
      );
    });

    // The daily question is the one event with no record of its own to
    // react to: what matters is `both_answered` flipping true, which is a
    // property of the *pair* of answers. So the subscription is only a
    // wake-up, and the actual check is a `today()` fetch — the same shape
    // QuestionsViewModel uses on the UI side.
    _answerUnsub = await _questionRepository?.subscribe(() {
      unawaited(_checkReveal());
    });
  }

  Future<void> _checkReveal() async {
    final questions = _questionRepository;
    final notifications = _notifications;
    final partnerId = _partnerId;
    if (questions == null || notifications == null || partnerId == null) {
      return;
    }
    try {
      final today = await questions.today();
      // A new day resets the latch — yesterday's reveal must not suppress
      // today's.
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      if (_revealCheckedOn != day) {
        _revealCheckedOn = day;
        _revealedToday = today.bothAnswered;
        // Nothing to announce on the first look of the day: if it's already
        // revealed we simply missed the moment (the service restarted), and
        // a notification about it now would be a lie about when it happened.
        return;
      }
      if (today.bothAnswered && !_revealedToday) {
        _revealedToday = true;
        notifications.report(
          () => notifications.reportReveal(partnerId: partnerId),
        );
      } else {
        _revealedToday = today.bothAnswered;
      }
    } catch (_) {
      // Server unreachable / no question today — try again on the next
      // answers event.
    }
  }

  Future<void> _render() async {
    // The home-screen widget has no re-post/re-animate cost like the
    // notification does, so it's refreshed unconditionally on every
    // render rather than behind the `_lastRendered` dedup below.
    await updatePartnerWidget(
      partnerName: _partnerName,
      status: _partnerStatus,
      partnerDevices: _partnerDevices,
    );

    final content = buildPartnerNotification(
      partnerName: _partnerName,
      status: _partnerStatus,
      partnerDevices: _partnerDevices,
    );

    // The activity-aware status-bar icon (kb/roadmap.md Wave 6): the same
    // ambient-line precedence `buildPartnerNotification` already resolved
    // internally, recomputed here (pure + cheap) so this isolate has the
    // `AmbientLine` itself rather than only its rendered text.
    // `notificationIconFor` never returns anything outside
    // `notificationIconNames`, so this can only ever hand
    // [KehaiForegroundTask.render] a name with a matching manifest entry.
    final iconKey = notificationIconFor(resolveAmbientLine(_partnerDevices));
    // Only worth pushing when it actually changed — see `render`'s doc
    // comment on why passing it unconditionally would be safe but wasteful
    // (an update is a merge, not a reset), and [KehaiForegroundTask.render]
    // treats a `null` iconKey as "leave it alone".
    final iconChanged = iconKey != _lastIconKey;

    // Android re-posts (and on some OEM skins, re-animates) the
    // notification on every update, so skip no-op renders — the 60s
    // repeat tick would otherwise churn it constantly. The icon is checked
    // separately from `content` (title/text) so an icon-only change can
    // still go out even on a tick where the rendered strings happen to be
    // identical to last time.
    if (content == _lastRendered && !iconChanged) return;
    _lastRendered = content;
    if (iconChanged) _lastIconKey = iconKey;
    await KehaiForegroundTask.render(
      content,
      iconKey: iconChanged ? iconKey : null,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Cheap upkeep: retry a connection we couldn't make at start, and
    // re-render so "away" / offline device glyphs age correctly even when
    // no realtime event has arrived.
    unawaited(() async {
      try {
        await _connect();
      } catch (_) {
        // Still unreachable — try again next tick.
      }
      await _render();
    }());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _statusUnsub?.call();
    _deviceUnsub?.call();
    _pingUnsub?.call();
    _doodleUnsub?.call();
    _instantUnsub?.call();
    _answerUnsub?.call();
    _statusUnsub = null;
    _deviceUnsub = null;
    _pingUnsub = null;
    _doodleUnsub = null;
    _instantUnsub = null;
    _answerUnsub = null;
    _notifications = null;
    _notifier = null;
    _heartbeatService?.stop();
    _vitalsService = null;
    await _locationPublisher?.stop();
    _locationPublisher = null;
    await _presenceService?.dispose();
    _presenceService = null;
    _pb = null;
  }
}
