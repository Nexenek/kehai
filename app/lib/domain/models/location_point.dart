import 'package:flutter/foundation.dart';

/// One stored point from the `locations` collection (kb/contracts.md
/// "Location"). Written server-side only — the OwnTracks ingest route is
/// the sole author, so this model is read-only by design.
///
/// Pure Dart on purpose: the PocketBase → [LocationPoint] mapping lives in
/// [LocationRepository.pointFromRecord] so the domain layer never imports
/// the client, and `latlong2` conversion happens in the map view.
@immutable
class LocationPoint {
  const LocationPoint({
    required this.id,
    required this.userId,
    required this.lat,
    required this.lon,
    required this.recorded,
    this.accuracy,
    this.battery,
    this.velocity,
  });

  final String id;
  final String userId;
  final double lat;
  final double lon;

  /// From OwnTracks' `tst` — when the *phone* took the fix, not when our
  /// server stored it. Everything user-facing ("as of 5m ago", the 24h
  /// staleness cutoff) is measured against this.
  final DateTime recorded;

  /// Reported accuracy radius in metres, if the tracker sent one.
  final double? accuracy;

  /// Phone battery percentage at fix time, if the tracker sent one.
  final double? battery;

  /// Speed in km/h, if the tracker sent one.
  final double? velocity;

  Duration ageAt(DateTime now) => now.difference(recorded);

  @override
  bool operator ==(Object other) =>
      other is LocationPoint &&
      other.id == id &&
      other.userId == userId &&
      other.lat == lat &&
      other.lon == lon &&
      other.recorded == recorded &&
      other.accuracy == accuracy &&
      other.battery == battery &&
      other.velocity == velocity;

  @override
  int get hashCode =>
      Object.hash(id, userId, lat, lon, recorded, accuracy, battery, velocity);

  @override
  String toString() =>
      'LocationPoint($userId, $lat, $lon, recorded: $recorded)';
}
