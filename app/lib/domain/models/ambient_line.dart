import 'package:flutter/foundation.dart';

import '../../ui/core/strings/app_strings.dart';
import 'device_status.dart';
import 'now_playing.dart';

/// Which rung of the partner-card ambient-line precedence produced this
/// line — kb/platform-desktop.md's "Telemetry contract (Phase 2a)":
/// "now_playing ♪ > activity > 'at their computer'/'on their phone'
/// (recent last_seen, low idle) > 'away' (idle > 5 min) > nothing recent."
enum AmbientLineKind { nowPlaying, activity, atComputer, onPhone, away }

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
AmbientLine? resolveAmbientLine(List<DeviceStatus> devices) {
  final online = devices.where((d) => d.isOnline).toList();
  if (online.isEmpty) return null;

  // now_playing: a Playing player anywhere beats a merely Paused one.
  NowPlaying? bestNowPlaying;
  for (final device in online) {
    final nowPlaying = device.nowPlaying;
    if (nowPlaying == null) continue;
    if (nowPlaying.state == NowPlayingState.playing) {
      bestNowPlaying = nowPlaying;
      break;
    }
    bestNowPlaying ??= nowPlaying;
  }
  if (bestNowPlaying != null) {
    return AmbientLine(
      kind: AmbientLineKind.nowPlaying,
      text: bestNowPlaying.marqueeText,
    );
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

  // Every online device is idle >= 5 min.
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
