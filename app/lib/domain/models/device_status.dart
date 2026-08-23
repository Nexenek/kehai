import 'package:flutter/foundation.dart';

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

  static const onlineWindow = Duration(minutes: 2);

  bool get isOnline =>
      DateTime.now().toUtc().difference(lastSeen.toUtc()) <= onlineWindow;
}
