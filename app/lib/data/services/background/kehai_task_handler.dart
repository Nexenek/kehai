import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../domain/models/device_status.dart';
import '../../../domain/models/partner_status.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/couple_repository.dart';
import '../../repositories/device_repository.dart';
import '../../repositories/status_repository.dart';
import '../device_info_service.dart';
import '../heartbeat_service.dart';
import '../pocketbase_client.dart';
import '../prefs_service.dart';
import '../presence/android/android_presence_service.dart';
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
/// 4. pushes rendered notification strings down to the service, and
/// 5. — when `shareLocation` is on — runs [LocationPublisher], the app's
///    own OwnTracks-compatible tracker (kb/contracts.md "Location"), and
///    keeps [PresenceService]'s `shareFocusedApp`/`shareUnknownApps`
///    opt-ins (kb/features.md "Focused-app status") in sync too — see
///    [_applySharingPrefs].
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
class KehaiTaskHandler extends TaskHandler {
  PocketBase? _pb;
  CoupleRepository? _coupleRepository;
  StatusRepository? _statusRepository;
  DeviceRepository? _deviceRepository;
  HeartbeatService? _heartbeatService;
  PresenceService? _presenceService;
  LocationPublisher? _locationPublisher;

  UnsubscribeFunc? _statusUnsub;
  UnsubscribeFunc? _deviceUnsub;

  String? _partnerName;
  String? _partnerId;
  PartnerStatus? _partnerStatus;
  List<DeviceStatus> _partnerDevices = const [];
  PartnerNotificationContent? _lastRendered;

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
    _coupleRepository = CoupleRepository(pb, auth);
    _statusRepository = StatusRepository(pb);
    _deviceRepository = DeviceRepository(pb);

    final presence = createPresenceService();
    _presenceService = presence;
    _heartbeatService = HeartbeatService(
      _deviceRepository!,
      const DeviceInfoService(),
      presenceService: presence,
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
  /// `shareUnknownApps`) and pushes each onto whichever live service
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
  }

  /// `FlutterForegroundTask.sendDataToTask` lands here — the instant path
  /// [KehaiForegroundTask.notifyPrefsChanged] uses so a sharing toggle
  /// flipped in the app (superpowers screen, sharing-settings dialog)
  /// reaches this isolate right away instead of waiting for the next 60s
  /// [onRepeatEvent] tick. The payload itself carries no information worth
  /// reading — any receipt just means "go re-read prefs".
  @override
  void onReceiveData(Object data) {
    unawaited(_applySharingPrefs());
  }

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

  Future<void> _refreshPartner() async {
    final partner = await _coupleRepository?.fetchPartner();
    _partnerId = partner?.id;
    _partnerName = partner?.name;
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
    // Android re-posts (and on some OEM skins, re-animates) the
    // notification on every update, so skip no-op renders — the 60s
    // repeat tick would otherwise churn it constantly.
    if (content == _lastRendered) return;
    _lastRendered = content;
    await KehaiForegroundTask.render(content);
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
    _statusUnsub = null;
    _deviceUnsub = null;
    _heartbeatService?.stop();
    await _locationPublisher?.stop();
    _locationPublisher = null;
    await _presenceService?.dispose();
    _presenceService = null;
    _pb = null;
  }
}
