import 'package:flutter/foundation.dart';

import '../../ui/core/strings/app_strings.dart';
import 'device_status.dart';

/// A UTC offset in minutes east of UTC — what `devices.timezone` actually
/// carries on the wire.
///
/// FIELD SEMANTICS NOTE: the server field is named `timezone`
/// (kb/features.md's "Timezone dual clocks" feature), and its column is
/// sized/documented as if it might hold a real IANA zone name like
/// "Europe/Warsaw". It doesn't, yet — Dart's SDK has no built-in IANA
/// timezone database (`DateTime.now().timeZoneName` returns a
/// platform-specific abbreviation such as "CEST", not a zone name), and
/// this batch adds no new package to get one. So [HeartbeatService] sends
/// the device's *current UTC offset* instead, encoded by [encode] as
/// "UTC+02:00" / "UTC-05:30" / "UTC+00:00". It still moves across a DST
/// transition the same way a real zone would — it just never carries a
/// place name, only "how far from UTC, right now".
@immutable
class UtcOffset {
  const UtcOffset(this.minutes);

  /// Minutes east of UTC (negative = west).
  final int minutes;

  factory UtcOffset.fromDuration(Duration offset) =>
      UtcOffset(offset.inMinutes);

  /// This device's own offset, right now.
  factory UtcOffset.now() =>
      UtcOffset.fromDuration(DateTime.now().timeZoneOffset);

  static final _wirePattern = RegExp(r'^UTC([+-])(\d{2}):(\d{2})$');

  /// Encodes as "UTC+02:00" / "UTC-05:30" / "UTC+00:00" — see the class
  /// doc comment for why this, and not a real zone name, is the wire
  /// format.
  String encode() {
    final sign = minutes < 0 ? '-' : '+';
    final abs = minutes.abs();
    final hh = (abs ~/ 60).toString().padLeft(2, '0');
    final mm = (abs % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hh:$mm';
  }

  /// Parses the wire format above. Null for anything else — including a
  /// real IANA name some future client might send; the dual-clock line
  /// just won't show for that device until it's expressed as an offset.
  static UtcOffset? parse(String? value) {
    if (value == null) return null;
    final match = _wirePattern.firstMatch(value);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final hh = int.parse(match.group(2)!);
    final mm = int.parse(match.group(3)!);
    return UtcOffset(sign * (hh * 60 + mm));
  }

  @override
  bool operator ==(Object other) =>
      other is UtcOffset && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => encode();
}

/// Picks the offset off whichever of the partner's devices most recently
/// reported one (by [DeviceStatus.lastSeen]) — devices with no, or an
/// unparseable, timezone are skipped rather than blanking the result.
UtcOffset? resolvePartnerUtcOffset(List<DeviceStatus> devices) {
  DeviceStatus? freshest;
  for (final device in devices) {
    if (UtcOffset.parse(device.timezone) == null) continue;
    if (freshest == null || device.lastSeen.isAfter(freshest.lastSeen)) {
      freshest = device;
    }
  }
  return freshest == null ? null : UtcOffset.parse(freshest.timezone);
}

/// "what time is it there" (kb/features.md "Timezone dual clocks"). Pure:
/// given my own offset, the partner's freshest one, and the current
/// instant in UTC, returns the partner-card line — or null when we're in
/// the same offset (nothing worth a whole line for) or theirs is unknown.
///
/// [nowUtc] must actually be UTC (`DateTime.now().toUtc()`) — the function
/// does plain offset arithmetic on it rather than relying on either
/// device's own timezone rules, which keeps it a pure, directly testable
/// function of its inputs.
String? resolveDualClockLine({
  required UtcOffset mine,
  required UtcOffset? theirs,
  required DateTime nowUtc,
}) {
  if (theirs == null || theirs == mine) return null;
  final theirLocal = nowUtc.add(Duration(minutes: theirs.minutes));
  final hh = theirLocal.hour.toString().padLeft(2, '0');
  final mm = theirLocal.minute.toString().padLeft(2, '0');
  final glyph = (theirLocal.hour >= 20 || theirLocal.hour < 6) ? '☾' : '☀';
  return AppStrings.theirTimeLine('$hh:$mm', glyph);
}
