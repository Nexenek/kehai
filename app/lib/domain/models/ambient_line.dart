import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../ui/core/strings/app_strings.dart';
import 'device_status.dart';
import 'utc_offset.dart';
import 'now_playing.dart';

/// Which rung of the partner-card ambient-line precedence produced this
/// line — kb/platform-desktop.md's "Telemetry contract (Phase 2a)":
/// "now_playing ♪ > activity > 'at their computer'/'on their phone'
/// (recent last_seen, low idle) > 'away' (idle > 5 min) > nothing recent."
enum AmbientLineKind { nowPlaying, activity, atComputer, onPhone, asleep, away }

@immutable
class AmbientLine {
  const AmbientLine({required this.kind, required this.text});

  final AmbientLineKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is AmbientLine && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'AmbientLine($kind, "$text")';
}

/// How long idle has to run before "at their computer"/"on their phone"
/// gives way to "away" — kb/platform-desktop.md: "'away' (idle > 5 min)".
const awayIdleThreshold = Duration(minutes: 5);

/// Pure precedence function over one partner's `devices` records — no
/// BuildContext, no clock injection needed beyond [DeviceStatus.isOnline]
/// itself, so it's directly unit-testable with hand-built records. Only
/// devices currently online are considered (the contract's "recent
/// last_seen" clause); returns null when nothing in the chain applies,
/// which is the signal for the caller to fall back to its existing offline
/// state.
/// How long a phone must sit untouched, during their night, before "away"
/// softens into "probably asleep".
const asleepIdleThreshold = Duration(minutes: 45);

/// The clock-free rung: a phone nobody has touched for THIS long reads as
/// asleep at any hour. The fixed night window alone was a bad model for
/// gremlin-hours sleepers (asleep at 05:00, up at 15:00): the night rung
/// gets the fast detection at classic hours, and once real sleep has piled
/// up this much idle, the hour of day stops mattering — which is also
/// exactly what carries a late sleeper past 08:00 without a flicker. Three
/// hours is long enough that an awake person has almost always touched
/// their phone, and the main false positive left (phone abandoned at home)
/// is usually preempted anyway: actively using any other device wins the
/// precedence chain before this rung is even asked.
const asleepDeepIdleThreshold = Duration(hours: 3);

/// Their-local hours treated as night for the asleep inference (>= 22:00 or
/// < 08:00 — generous on purpose; "probably" carries the uncertainty).
bool _isNightHour(int hour) => hour >= 22 || hour < 8;

bool _probablyAsleep(List<DeviceStatus> online, DateTime nowUtc) {
  bool phoneIdleAtLeast(Duration threshold) => online.any(
    (d) => d.kind == 'phone' && (d.idleSeconds ?? 0) >= threshold.inSeconds,
  );

  // Deep idle needs no timezone: three hours of untouched phone means the
  // same thing in every country.
  if (phoneIdleAtLeast(asleepDeepIdleThreshold)) return true;

  final offset = resolvePartnerUtcOffset(online);
  if (offset == null) return false;
  final theirHour = nowUtc.add(Duration(minutes: offset.minutes)).hour;
  if (!_isNightHour(theirHour)) return false;
  return phoneIdleAtLeast(asleepIdleThreshold);
}

AmbientLine? resolveAmbientLine(
  List<DeviceStatus> devices, {
  DateTime? nowUtc,
}) {
  final online = devices.where((d) => d.isOnline).toList();
  if (online.isEmpty) return null;

  // now_playing: only an actually-Playing player counts as listening.
  // Android (and desktops) keep a lingering Paused session around long
  // after the music was paused or the player closed — showing that as
  // "listening" reads as stale/wrong to the partner, so paused sessions
  // fall through to activity/presence instead.
  for (final device in online) {
    final nowPlaying = device.nowPlaying;
    if (nowPlaying != null && nowPlaying.state == NowPlayingState.playing) {
      return AmbientLine(
        kind: AmbientLineKind.nowPlaying,
        text: nowPlaying.marqueeText,
      );
    }
  }

  for (final device in online) {
    final activity = device.activity;
    if (activity != null && activity.isNotEmpty) {
      return AmbientLine(kind: AmbientLineKind.activity, text: activity);
    }
  }

  // "at their computer"/"on their phone": online with low (or unreported —
  // no signal to say otherwise) idle. Sort so the freshest device wins
  // when more than one is online.
  final byFreshness = [...online]
    ..sort((a, b) => (a.idleSeconds ?? 0).compareTo(b.idleSeconds ?? 0));
  for (final device in byFreshness) {
    final idle = device.idleSeconds;
    if (idle == null || idle < awayIdleThreshold.inSeconds) {
      return AmbientLine(
        kind: device.kind == 'phone'
            ? AmbientLineKind.onPhone
            : AmbientLineKind.atComputer,
        text: device.kind == 'phone'
            ? AppStrings.ambientOnPhone
            : AppStrings.ambientAtComputer,
      );
    }
  }

  // Every online device is idle >= 5 min. If it's the middle of the night
  // where THEY are and their phone has been untouched for a long while,
  // "away" is almost certainly "asleep" — say the warmer thing. Derived
  // entirely from telemetry we already have (phone idle + the timezone the
  // dual-clock feature sends); "probably" keeps it honest.
  if (_probablyAsleep(online, nowUtc ?? clock.now().toUtc())) {
    return const AmbientLine(
      kind: AmbientLineKind.asleep,
      text: AppStrings.ambientAsleep,
    );
  }
  return const AmbientLine(
    kind: AmbientLineKind.away,
    text: AppStrings.ambientAway,
  );
}

/// The low-battery/charging glyph kind for the partner's phone, per
/// design-language.md's signature element ("tiny low-battery pixel glyph"
/// + "charging bolt").
enum BatteryGlyphKind { none, low, charging }

@immutable
class BatteryGlyphInfo {
  const BatteryGlyphInfo({required this.kind, this.percent, this.tooltip = ''});

  static const none = BatteryGlyphInfo(kind: BatteryGlyphKind.none);

  final BatteryGlyphKind kind;
  final double? percent;
  final String tooltip;
}

/// Pure precedence function for the partner's phone battery glyph. Looks
/// at the most-recently-seen `phone` device that has reported a battery
/// reading at all — not gated on [DeviceStatus.isOnline], since a phone
/// that just dropped offline at 4% is still worth flagging.
BatteryGlyphInfo resolvePhoneBattery(List<DeviceStatus> devices) {
  DeviceStatus? phone;
  for (final device in devices) {
    if (device.kind != 'phone' || device.battery == null) continue;
    if (phone == null || device.lastSeen.isAfter(phone.lastSeen))
      phone = device;
  }
  if (phone == null) return BatteryGlyphInfo.none;

  final battery = phone.battery!;
  if (phone.charging == true) {
    return BatteryGlyphInfo(
      kind: BatteryGlyphKind.charging,
      percent: battery,
      tooltip: AppStrings.chargingTooltip,
    );
  }
  if (battery <= 20) {
    return BatteryGlyphInfo(
      kind: BatteryGlyphKind.low,
      percent: battery,
      tooltip: '${AppStrings.batteryLowTooltip} (${battery.round()}%)',
    );
  }
  return BatteryGlyphInfo.none;
}
