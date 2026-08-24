import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'vitals_channel.dart';

/// Turns Health Connect readings into the heartbeat's `steps_today` /
/// `heart_rate` keys (kb/contracts.md, heartbeat telemetry), following the
/// same only-provided-keys + explicit-null-to-clear rules the rest of
/// [HeartbeatService]'s fields follow.
///
/// Three things this owns that the channel deliberately doesn't:
///
/// 1. **The off switch.** [enabled] is the `shareVitals` opt-in, off by
///    default like every sharing toggle. While it's off (or we're not on
///    Android) [telemetry] answers instantly without touching the channel
///    — the OS is never even asked.
/// 2. **Cadence.** The heartbeat runs every 30s; a Health Connect read is
///    an IPC round-trip to another app's process, and a watch that syncs
///    every 10–30 minutes has nothing new to say in between. So readings
///    are cached for [refreshInterval] (5 minutes) and every heartbeat in
///    between re-sends the cached value.
/// 3. **Ageing out.** A sample the partner's card is beating to must stop
///    being sent once it's older than [_sampleWindow], and stopping means
///    one explicit `null` — the contract's way of clearing a value, since
///    an absent key means "leave what you had".
///
/// Everything time-related goes through `clock.now()` so the cadence and
/// ageing rules are testable with `fakeAsync`/`withClock` rather than by
/// waiting five real minutes.
class VitalsService {
  VitalsService({
    VitalsChannel channel = const VitalsChannel(),
    @visibleForTesting bool? isSupported,
    // Two minutes, down from the original five after real-world use ("the
    // heart pulling is still slow"): a Health Connect read is one cheap
    // IPC, so the polling leg might as well be snappy — the slow leg is
    // the watch's own batch-sync into Health Connect, which no app-side
    // interval can hurry.
    @visibleForTesting this.refreshInterval = const Duration(minutes: 2),
  }) : _channel = channel,
       _isSupported = isSupported ?? Platform.isAndroid;

  final VitalsChannel _channel;
  final bool _isSupported;

  /// How long a reading is reused before the channel is asked again.
  final Duration refreshInterval;

  /// How old a heart-rate sample may be and still be worth reporting. Kept
  /// in step with the native read window (`KehaiVitalsPlugin`'s two hours):
  /// the native side won't return anything older, and this catches the case
  /// where a cached reading itself ages past the line between reads.
  static const _sampleWindow = Duration(hours: 2);

  /// The heartbeat contract's own bounds (server: 0..200000 steps,
  /// 20..250 bpm). A reading outside them is dropped rather than clamped —
  /// clamping would invent a number, and a rejected heartbeat would take
  /// every *other* telemetry key down with it.
  static const _maxSteps = 200000;
  static const _minBpm = 20;
  static const _maxBpm = 250;

  /// The `shareVitals` opt-in. Pushed in by whichever isolate owns the
  /// heartbeat — `AppController.setShareVitals` on the UI side,
  /// `KehaiTaskHandler._applySharingPrefs` in the foreground service.
  bool get enabled => _enabled;
  bool _enabled = false;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    // Turning it back on shouldn't hand out a reading from before it was
    // turned off.
    if (!value) invalidateCache();
  }

  VitalsReading? _cached;
  DateTime? _lastReadAt;

  /// Drops the cached reading so the next [telemetry] goes back to the
  /// channel, whatever the 5-minute cadence would otherwise say.
  ///
  /// Called when the app comes to the foreground (see
  /// `KehaiTaskHandler.onReceiveData`). Without
  /// READ_HEALTH_DATA_IN_BACKGROUND every read from the backgrounded
  /// service throws and the cache holds nothing but nulls — so the moment
  /// the app IS on screen is the one moment a read is guaranteed to work,
  /// and it would be a waste to spend it re-sending a stale cache. This is
  /// what the user was doing by hand when they toggled the row off and on
  /// to force an update through.
  void invalidateCache() {
    _cached = null;
    _lastReadAt = null;
  }

  /// Whether a heart-rate sample was actually put on the wire — the state
  /// the one-shot clearing null needs.
  bool _sentHeartRate = false;

  /// Whether anything at all was reported, so turning the opt-in off knows
  /// whether there's something on the partner's side to clear.
  bool _sentAnything = false;

  /// The heartbeat's vitals fields, or null when there's nothing to say.
  ///
  /// Only-provided-keys, so an unknown value simply isn't a key here rather
  /// than being sent as a null — except for the two moments where a
  /// previously-reported value has to be actively cleared: the sample
  /// ageing out, and the user turning the opt-in off.
  Future<Map<String, dynamic>?> telemetry() async {
    if (!_isSupported) return null;
    if (!_enabled) return _clearingFields();

    final reading = await _read();
    if (reading == null) return null;

    final fields = <String, dynamic>{};

    final steps = reading.stepsToday;
    if (steps != null && steps >= 0 && steps <= _maxSteps) {
      fields['steps_today'] = steps;
    }

    final sample = _reportableSample(reading);
    if (sample != null) {
      fields['heart_rate'] = {
        'bpm': sample.bpm,
        'at': sample.at.toIso8601String(),
      };
      _sentHeartRate = true;
    } else if (_sentHeartRate) {
      // Nothing fresh any more and the partner's card is still beating to
      // whatever we sent last — clear it, once.
      fields['heart_rate'] = null;
      _sentHeartRate = false;
    }

    if (fields.isEmpty) return null;
    if (fields.values.any((value) => value != null)) _sentAnything = true;
    return fields;
  }

  /// The opt-in is off. That's an instant answer — but "off" has to mean
  /// the partner stops seeing a heart rate, not that the last one we sent
  /// sits on their screen forever, so the first heartbeat after the switch
  /// flips carries explicit nulls (kb/README.md's standing constraint:
  /// "every tracking feature ships with an easy, guilt-free off switch").
  /// Exactly one such heartbeat, then silence.
  Map<String, dynamic>? _clearingFields() {
    if (!_sentAnything) return null;
    _sentAnything = false;
    _sentHeartRate = false;
    return <String, dynamic>{'steps_today': null, 'heart_rate': null};
  }

  /// The cached reading, refreshed at most once per [refreshInterval].
  Future<VitalsReading?> _read() async {
    final now = clock.now();
    final last = _lastReadAt;
    final cached = _cached;
    if (cached != null &&
        last != null &&
        now.difference(last) < refreshInterval) {
      return cached;
    }
    final reading = await _channel.read();
    _lastReadAt = now;
    _cached = reading;
    return reading;
  }

  /// The reading's heart-rate sample, if it exists, is in range, and is
  /// still inside [_sampleWindow].
  _Sample? _reportableSample(VitalsReading reading) {
    final bpm = reading.bpm;
    final at = reading.bpmAt;
    if (bpm == null || at == null) return null;
    if (bpm < _minBpm || bpm > _maxBpm) return null;
    if (clock.now().toUtc().difference(at) > _sampleWindow) return null;
    return _Sample(bpm, at);
  }
}

class _Sample {
  const _Sample(this.bpm, this.at);
  final int bpm;
  final DateTime at;
}
