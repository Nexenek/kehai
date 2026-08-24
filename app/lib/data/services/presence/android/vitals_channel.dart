import 'package:flutter/services.dart';

/// Whether this phone can talk to Health Connect at all
/// (`HealthConnectClient.getSdkStatus`).
enum VitalsAvailability {
  /// Health Connect is installed and current — the only state in which
  /// permissions can be asked for or data read.
  available,

  /// The provider is there but too old for the client library. The user has
  /// to update it from the Play Store; we can't do anything about it here.
  needsUpdate,

  /// No Health Connect on this device (or an Android older than 9, or a
  /// non-Android platform). The vitals row disables itself.
  unavailable,
}

/// One raw reading from the native side: today's steps and the newest
/// heart-rate sample. Every field is independently nullable — a phone with
/// a step-counting watch but no heart-rate sensor is a perfectly normal
/// phone, and so is one whose watch simply hasn't synced yet today.
class VitalsReading {
  const VitalsReading({this.stepsToday, this.bpm, this.bpmAt});

  /// Steps since *local* midnight (the native side aggregates over a local
  /// time range, so this is the phone's today).
  final int? stepsToday;

  /// The newest sample's beats per minute, rounded.
  final int? bpm;

  /// When that sample was **measured**, UTC — not when we read it. Watches
  /// batch-sync, so the two can be an hour apart, and the partner card only
  /// beats a heart it knows the age of (`HeartRateSample.freshWindow`).
  final DateTime? bpmAt;

  static const empty = VitalsReading();

  bool get isEmpty => stepsToday == null && bpm == null;

  /// Parses the `{stepsToday, bpm, bpmAt}` map `KehaiVitalsPlugin.readVitals`
  /// returns. Anything malformed degrades to null rather than throwing:
  /// this runs inside the heartbeat loop.
  ///
  /// A sample with a bpm but no readable timestamp is dropped entirely —
  /// the contract needs both, and inventing "measured now" for a reading
  /// that could be two hours old is exactly the small lie
  /// [HeartRateSample] exists to avoid.
  static VitalsReading fromChannel(Object? raw) {
    if (raw is! Map) return empty;
    final steps = raw['stepsToday'];
    final bpm = raw['bpm'];
    final at = DateTime.tryParse(raw['bpmAt'] as String? ?? '');
    return VitalsReading(
      stepsToday: steps is num ? steps.round() : null,
      bpm: (bpm is num && at != null) ? bpm.round() : null,
      bpmAt: bpm is num ? at?.toUtc() : null,
    );
  }
}

/// The thin Dart half of the `app.kehai/vitals` platform channel. Holds no
/// logic beyond "call the channel, don't throw" — the cadence, caching and
/// only-provided-keys work all live in [VitalsService], which is where the
/// tests are.
///
/// The Kotlin half is registered on BOTH Flutter engines (see
/// `KehaiVitalsPlugin`), so [read] works from the foreground service's
/// background isolate as well as the UI one. [requestPermissions] is the
/// exception: it needs an Activity, so it only does anything from the app.
class VitalsChannel {
  const VitalsChannel();

  static const _methods = MethodChannel('app.kehai/vitals');

  Future<VitalsAvailability> availability() async {
    switch (await _invoke<String>('getAvailability')) {
      case 'available':
        return VitalsAvailability.available;
      case 'needsUpdate':
        return VitalsAvailability.needsUpdate;
      default:
        return VitalsAvailability.unavailable;
    }
  }

  /// Whether READ_STEPS and READ_HEART_RATE are both granted. The
  /// background-read permission is a best-effort extra the native side
  /// deliberately leaves out of this answer — without it vitals still
  /// update while Kehai is on screen.
  Future<bool> hasPermissions() async =>
      await _invoke<bool>('hasPermissions') ?? false;

  /// Opens Health Connect's own permission sheet and answers with whether
  /// the reads ended up granted. False from the background isolate (no
  /// Activity there) and on every non-Android platform.
  Future<bool> requestPermissions() async =>
      await _invoke<bool>('requestPermissions') ?? false;

  Future<VitalsReading> read() async =>
      VitalsReading.fromChannel(await _invoke<Object?>('readVitals'));

  /// Every call is swallowed on failure — no channel (tests, desktop), no
  /// provider, a revoked grant: the answer is "no reading", never an
  /// exception surfacing in the heartbeat loop.
  Future<T?> _invoke<T>(String method) async {
    try {
      return await _methods.invokeMethod<T>(method);
    } catch (_) {
      return null;
    }
  }
}
