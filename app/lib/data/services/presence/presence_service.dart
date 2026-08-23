import 'package:flutter/foundation.dart';

import '../../../domain/models/now_playing.dart';

/// A snapshot of "what's this device up to right now" — now-playing media,
/// idle seconds, and (on devices that have a battery) charge level +
/// charging flag — for the heartbeat's presence payload
/// (kb/platform-desktop.md "Telemetry contract (Phase 2a)").
///
/// Every field is nullable and means "this device has no signal for that",
/// which the heartbeat translates into "don't write that key" (see
/// [HeartbeatService]). Desktops leave [battery]/[charging] null; phones
/// fill them from `ACTION_BATTERY_CHANGED` (kb/platform-android.md's
/// "Battery/charging" row).
@immutable
class DevicePresence {
  const DevicePresence({
    this.nowPlaying,
    this.idleSeconds,
    this.battery,
    this.charging,
    this.activity,
  });

  static const empty = DevicePresence();

  final NowPlaying? nowPlaying;
  final int? idleSeconds;

  /// 0–100, or null on a device that doesn't report a battery level.
  final double? battery;

  /// Whether the device is plugged in, or null if unknown.
  final bool? charging;

  /// The friendly "what app they're focused on" label (kb/features.md
  /// "Focused-app status"), already run through `ActivityMapper` — null
  /// means either the per-device `shareFocusedApp` opt-in is off, or the
  /// current foreground app has no signal/mapping to report. Feeds the
  /// `activity` telemetry key, one rung below `now_playing` in the ambient
  /// line's precedence.
  final String? activity;

  @override
  bool operator ==(Object other) =>
      other is DevicePresence &&
      other.nowPlaying == nowPlaying &&
      other.idleSeconds == idleSeconds &&
      other.battery == battery &&
      other.charging == charging &&
      other.activity == activity;

  @override
  int get hashCode =>
      Object.hash(nowPlaying, idleSeconds, battery, charging, activity);

  @override
  String toString() =>
      'DevicePresence(nowPlaying: $nowPlaying, idleSeconds: $idleSeconds, '
      'battery: $battery, charging: $charging, activity: $activity)';
}

/// Observes device presence for the heartbeat. Implementations must
/// degrade gracefully — an unsupported desktop/compositor/OS just means
/// [DevicePresence.empty] forever, never a crash (see
/// kb/platform-desktop.md's "Idle / presence" table: "pick per-desktop at
/// runtime, degrade gracefully").
abstract class PresenceService {
  /// The most recently observed reading. [DevicePresence.empty] before the
  /// first poll completes (or forever, for a platform stub).
  DevicePresence get current;

  /// Emits whenever [current] changes.
  Stream<DevicePresence> get onChange;

  /// Starts observing. Safe to call more than once.
  Future<void> start();

  /// Releases any OS resources (bus connections, timers). Owned by whoever
  /// constructed the service — [start]'s caller does not need to call this.
  Future<void> dispose();
}
