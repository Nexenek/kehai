import 'package:flutter/foundation.dart';

import 'heart_rate_sample.dart';
import 'now_playing.dart';

/// A `devices` record — used to light up the phone/desktop glyphs on the
/// partner card, and (per kb/platform-desktop.md's "Telemetry contract
/// (Phase 2a)") to drive the ambient line + battery glyph: [nowPlaying],
/// [idleSeconds], [battery]/[charging], [activity]. "Online" = last_seen
/// within the last 2 minutes (heartbeat interval is 30s, so a 2-minute
/// window tolerates a few missed beats).
@immutable
class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.kind,
    required this.lastSeen,
    this.nowPlaying,
    this.idleSeconds,
    this.battery,
    this.charging,
    this.activity,
    this.timezone,
    this.stepsToday,
    this.heartRate,
  });

  final String id;
  final String ownerId;
  final String name;
  final String kind; // phone | desktop | tablet | portal
  final DateTime lastSeen;

  /// `now_playing` — null means nothing playing on this device.
  final NowPlaying? nowPlaying;

  /// `idle_seconds` — null means this device doesn't report idle time.
  final int? idleSeconds;

  /// `battery` — 0-100, null means this device doesn't report battery.
  final double? battery;

  /// `charging` — null means this device doesn't report charging state.
  final bool? charging;

  /// `activity` — free-form text ≤100 chars, null/empty means none set.
  final String? activity;

  /// `timezone` — this device's UTC offset, wire-encoded as "UTC+02:00"
  /// (see `utc_offset.dart`'s [UtcOffset] for why it's an offset and not a
  /// real IANA zone name). Null/empty means this device hasn't reported
  /// one.
  final String? timezone;

  /// `steps_today` — steps since local midnight, from Health Connect
  /// (smartwatch vitals wave). Null means unreported/opted out; the server
  /// stores 0 for both "never reported" and "cleared", so the repository
  /// maps 0 to null the same way it does for battery.
  final int? stepsToday;

  /// `heart_rate` — latest Health Connect sample with its own measured-at
  /// timestamp (see [HeartRateSample.isFresh]). Null means unreported.
  final HeartRateSample? heartRate;

  static const onlineWindow = Duration(minutes: 2);

  bool get isOnline =>
      DateTime.now().toUtc().difference(lastSeen.toUtc()) <= onlineWindow;
}
