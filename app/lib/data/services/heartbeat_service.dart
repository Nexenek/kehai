import 'dart:async';

import '../../domain/models/now_playing.dart';
import '../../domain/models/utc_offset.dart';
import '../repositories/device_repository.dart';
import 'device_info_service.dart';
import 'presence/presence_service.dart';

/// Sends a heartbeat immediately, then every 30s while [start] is active,
/// plus an out-of-band heartbeat the moment now-playing track/state changes
/// or idle time crosses the 5-minute "away" boundary — kb/platform-desktop.md
/// "Telemetry contract (Phase 2a)": "Cadence: 30s timer + immediate push on
/// now-playing/idle change". Call [pingNow] again on app resume (spec:
/// "every 30s while app is open + on resume"). Errors are swallowed — a
/// missed heartbeat just means the device-source glyph goes dim for a bit,
/// not worth surfacing to the user.
///
/// [presenceService] is optional and injected so this class stays testable
/// without touching D-Bus/WinRT/Android — a fake [PresenceService] driven
/// by a `StreamController` is enough to exercise the immediate-heartbeat
/// and now_playing-clearing logic below.
class HeartbeatService {
  HeartbeatService(
    this._deviceRepository,
    this._deviceInfoService, {
    PresenceService? presenceService,
  }) : _presenceService = presenceService;

  final DeviceRepository _deviceRepository;
  final DeviceInfoService _deviceInfoService;
  final PresenceService? _presenceService;

  Timer? _timer;
  StreamSubscription<DevicePresence>? _presenceSub;
  static const _interval = Duration(seconds: 30);
  static const _awayThresholdSeconds = 5 * 60;

  // What the *previous presence reading* looked like — used to detect a
  // change worth an out-of-band heartbeat.
  NowPlaying? _lastObservedNowPlaying;
  bool _lastObservedAway = false;
  bool? _lastObservedCharging;

  // What the *last heartbeat body* actually contained — used to know when
  // a key needs an explicit `null` to clear a previously-reported value
  // (contract: "only provided keys are written ... send explicit
  // null/empty to clear").
  NowPlaying? _lastSentNowPlaying;
  int? _lastSentIdleSeconds;
  double? _lastSentBattery;
  bool? _lastSentCharging;
  String? _lastSentActivity;

  void start() {
    pingNow();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => pingNow());

    final presence = _presenceService;
    if (presence != null) {
      presence.start();
      _presenceSub?.cancel();
      _presenceSub = presence.onChange.listen(_onPresenceChanged);
    }
  }

  void _onPresenceChanged(DevicePresence presence) {
    // `activity` deliberately does NOT get an out-of-band beat: alt-tabbing
    // or switching windows can change it many times a minute, and unlike a
    // track/away/charging flip that's genuinely no more urgent than the
    // regular 30s cadence already covers — mirrors "a battery level ticking
    // down alone does not [trigger one]" below.
    final trackChanged = presence.nowPlaying != _lastObservedNowPlaying;
    final away = (presence.idleSeconds ?? 0) >= _awayThresholdSeconds;
    final awayCrossed =
        presence.idleSeconds != null && away != _lastObservedAway;
    // Plugging in / unplugging is a state the partner card actually draws
    // (the charging bolt glyph), so it earns an out-of-band beat the same
    // way a track change does. The *level* creeping down by a percent does
    // not — that rides along on the next 30s tick.
    final chargingFlipped =
        presence.charging != null && presence.charging != _lastObservedCharging;

    _lastObservedNowPlaying = presence.nowPlaying;
    if (presence.idleSeconds != null) _lastObservedAway = away;
    if (presence.charging != null) _lastObservedCharging = presence.charging;

    if (trackChanged || awayCrossed || chargingFlipped) {
      pingNow();
    }
  }

  Future<void> pingNow() async {
    try {
      final name = await _deviceInfoService.deviceName;
      final presence = _presenceService?.current ?? DevicePresence.empty;
      final fields = _presenceFields(presence);
      // Timezone (dual clocks, kb/features.md) is always computable — no
      // opt-in, no platform channel — so unlike the presence-driven keys
      // above it's simply sent on every heartbeat rather than tracked for
      // an explicit-null clear.
      fields['timezone'] = UtcOffset.now().encode();
      await _deviceRepository.sendHeartbeat(
        kind: _deviceInfoService.kind,
        name: name,
        extra: fields,
      );
      _lastSentNowPlaying = presence.nowPlaying;
      _lastSentIdleSeconds = presence.idleSeconds;
      _lastSentBattery = presence.battery;
      _lastSentCharging = presence.charging;
      _lastSentActivity = presence.activity;
    } catch (_) {
      // Best-effort — next timer tick (or the next resume) will retry.
    }
  }

  /// Only-provided-keys + explicit-null-to-clear, per the contract.
  Map<String, dynamic> _presenceFields(DevicePresence presence) {
    final fields = <String, dynamic>{};

    if (presence.nowPlaying != null) {
      fields['now_playing'] = presence.nowPlaying!.toJson();
    } else if (_lastSentNowPlaying != null) {
      fields['now_playing'] = null; // a previously-reported track stopped
    }

    if (presence.idleSeconds != null) {
      fields['idle_seconds'] = presence.idleSeconds;
    } else if (_lastSentIdleSeconds != null) {
      fields['idle_seconds'] = null;
    }

    // Phones report these (kb/platform-android.md "Battery/charging"); the
    // desktop presence paths leave them null forever, which per the
    // contract means the keys are simply never written.
    if (presence.battery != null) {
      fields['battery'] = presence.battery;
    } else if (_lastSentBattery != null) {
      fields['battery'] = null;
    }

    if (presence.charging != null) {
      fields['charging'] = presence.charging;
    } else if (_lastSentCharging != null) {
      fields['charging'] = null;
    }

    // `activity` — same only-present-keys/explicit-null-clears shape as
    // now_playing above. Absent means either the shareFocusedApp opt-in is
    // off or the mapper had nothing to say about the foreground app; either
    // way a previously-reported value needs the explicit null to clear.
    if (presence.activity != null) {
      fields['activity'] = presence.activity;
    } else if (_lastSentActivity != null) {
      fields['activity'] = null;
    }

    return fields;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _presenceSub?.cancel();
    _presenceSub = null;
  }
}
