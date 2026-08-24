import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'device_status.dart';

/// Resolved smartwatch vitals for display (kb/features.md's smartwatch-
/// vitals wave): the partner's latest heart rate + steps today, already
/// gated by freshness so every renderer can trust these fields directly
/// rather than re-checking [HeartRateSample.isFresh] or `lastSeen` itself.
/// Mirrors the shape of `resolvePhoneBattery`/`resolvePartnerUtcOffset` in
/// this same package — a pure function over the partner's `devices` list,
/// no BuildContext.
@immutable
class PartnerVitals {
  const PartnerVitals({this.bpm, this.stepsToday});

  static const none = PartnerVitals();

  /// The freshest phone's heart-rate sample, only when it's still fresh
  /// (`HeartRateSample.freshWindow`, 45 min). Null means: no heart, no bpm
  /// text — the rendered line takes zero space for this half.
  final int? bpm;

  /// Steps since local midnight, only when the phone that reported them was
  /// last seen within [stepsFreshWindow]. Null hides the steps half.
  final int? stepsToday;

  /// True when neither half has anything to show — the caller's cue to
  /// render zero-height for the whole vitals line.
  bool get isEmpty => bpm == null && stepsToday == null;

  @override
  bool operator ==(Object other) =>
      other is PartnerVitals && other.bpm == bpm && other.stepsToday == stepsToday;

  @override
  int get hashCode => Object.hash(bpm, stepsToday);
}

/// How stale a phone's `last_seen` may be and still let its `steps_today`
/// show — separate from (and much tighter than) the heart-rate freshness
/// window, since steps are a running daily total rather than a point-in-time
/// reading.
const stepsFreshWindow = Duration(hours: 2);

/// Picks the partner's most-recently-seen `phone` device — vitals only ever
/// come from a phone (Health Connect lives there), never desktop/tablet/
/// portal.
DeviceStatus? _freshestPhone(List<DeviceStatus> devices) {
  DeviceStatus? phone;
  for (final device in devices) {
    if (device.kind != 'phone') continue;
    if (phone == null || device.lastSeen.isAfter(phone.lastSeen)) {
      phone = device;
    }
  }
  return phone;
}

/// Pure precedence function over one partner's `devices` records — see the
/// class doc on [PartnerVitals]. [nowUtc] must actually be UTC; defaults to
/// `clock.now().toUtc()` so fakeAsync tests can pin it.
PartnerVitals resolvePartnerVitals(List<DeviceStatus> devices, {DateTime? nowUtc}) {
  final now = nowUtc ?? clock.now().toUtc();
  final phone = _freshestPhone(devices);
  if (phone == null) return PartnerVitals.none;

  final heartRate = phone.heartRate;
  final bpm = (heartRate != null && heartRate.isFresh(now)) ? heartRate.bpm : null;

  final stepsToday = phone.stepsToday;
  final stepsFresh =
      now.difference(phone.lastSeen.toUtc()) <= stepsFreshWindow;
  final steps = (stepsToday != null && stepsFresh) ? stepsToday : null;

  return PartnerVitals(bpm: bpm, stepsToday: steps);
}
