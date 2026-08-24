import 'package:flutter/foundation.dart';

/// A `devices.heart_rate` value — the most recent heart-rate sample Health
/// Connect had when the phone last heartbeated, carried WITH its own
/// timestamp because watches sync in batches: by the time the phone sees a
/// reading it can already be an hour old, and a heart beating at a stale
/// BPM would be a small lie. [isFresh] is the one gate every renderer uses.
@immutable
class HeartRateSample {
  const HeartRateSample({required this.bpm, required this.at});

  final int bpm;

  /// When the sample was *measured* (not when it was reported), UTC.
  final DateTime at;

  /// How old a sample may be and still drive the beating heart. Generous on
  /// purpose: most watches only sync every 10–30 minutes, and "her heart a
  /// little while ago" still beats warmer than nothing.
  static const freshWindow = Duration(minutes: 45);

  bool isFresh(DateTime nowUtc) => nowUtc.difference(at) <= freshWindow;

  static HeartRateSample? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final bpm = json['bpm'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (bpm is! num || at == null) return null;
    return HeartRateSample(bpm: bpm.round(), at: at.toUtc());
  }

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'at': at.toUtc().toIso8601String(),
  };
}
