import 'package:flutter/foundation.dart';

import '../../../domain/models/now_playing.dart';

/// A snapshot of "what's this device up to right now" — now-playing media
/// + idle seconds — for the heartbeat's presence payload
/// (kb/platform-desktop.md "Telemetry contract (Phase 2a)").
@immutable
class DevicePresence {
  const DevicePresence({this.nowPlaying, this.idleSeconds});

  static const empty = DevicePresence();

  final NowPlaying? nowPlaying;
  final int? idleSeconds;

  @override
  bool operator ==(Object other) =>
      other is DevicePresence && other.nowPlaying == nowPlaying && other.idleSeconds == idleSeconds;

  @override
  int get hashCode => Object.hash(nowPlaying, idleSeconds);

  @override
  String toString() => 'DevicePresence(nowPlaying: $nowPlaying, idleSeconds: $idleSeconds)';
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
