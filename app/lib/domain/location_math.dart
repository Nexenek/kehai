import 'dart:math' as math;

import '../ui/core/strings/app_strings.dart';
import 'models/ghost_state.dart';
import 'models/location_point.dart';

/// Mean Earth radius (IUGG), in km.
const double earthRadiusKm = 6371.0088;

/// Great-circle distance between two coordinates, in kilometres.
///
/// Client-side by contract (kb/contracts.md "Distance-apart": "client-side
/// haversine between both users' latest points") — the server never
/// computes or stores it, so neither of us has a "how far apart were they
/// on the 4th" row sitting in a database.
double haversineKm({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const rad = math.pi / 180.0;
  final dLat = (lat2 - lat1) * rad;
  final dLon = (lon2 - lon1) * rad;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * rad) *
          math.cos(lat2 * rad) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  // clamp guards asin() against a hair over 1.0 from float error at
  // antipodal points.
  return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Past this age a point stops being "where they are" and becomes "where
/// they were" — kb/contracts.md: "hide if either point older than 24h".
const Duration stalePointAge = Duration(hours: 24);

/// How fresh the partner's last point has to be to still be worth showing a
/// distance for *while they're paused*.
///
/// The contract's rule is "ghosted-with-no-fresh-point", and `ghost_until`
/// doesn't record when the pause *started*, so there's no way to ask "is
/// this point from before the pause". A point from the last few minutes is
/// one the tracker sent right as they hit pause and is still true; anything
/// older is a leftover, and quoting a distance from it would be exactly the
/// kind of "silently stale" the honest-pause design exists to avoid.
const Duration ghostFreshPointWindow = Duration(minutes: 15);

/// Under this, "apart" is the wrong word — it's inside GPS noise.
const double togetherThresholdKm = 0.05;

/// The partner-card / map line: "~4.2 km apart ♡", or null when it should
/// be hidden entirely (kb/contracts.md "Distance-apart").
///
/// Hidden when: either of us has no point at all; either point is older
/// than [stalePointAge]; or the partner is paused and their last point
/// isn't fresh (see [ghostFreshPointWindow]). One decimal under 10 km,
/// whole kilometres above it.
///
/// [myGhost] matters too: while *I'm* paused my own stored point stops
/// being updated, so quoting a distance off it would mislead me about a
/// number they can't see the same way.
String? formatDistanceApart({
  required LocationPoint? mine,
  required LocationPoint? theirs,
  GhostState partnerGhost = GhostState.off,
  GhostState myGhost = GhostState.off,
  DateTime? now,
}) {
  if (mine == null || theirs == null) return null;
  final at = now ?? DateTime.now();

  if (mine.ageAt(at) > stalePointAge) return null;
  if (theirs.ageAt(at) > stalePointAge) return null;
  if (partnerGhost.isActive && theirs.ageAt(at) > ghostFreshPointWindow) {
    return null;
  }
  if (myGhost.isActive && mine.ageAt(at) > ghostFreshPointWindow) return null;

  final km = haversineKm(
    lat1: mine.lat,
    lon1: mine.lon,
    lat2: theirs.lat,
    lon2: theirs.lon,
  );
  if (km < togetherThresholdKm) return AppStrings.distanceTogether;
  return AppStrings.distanceApart(formatKm(km));
}

/// Just the number: one decimal under 10 km ("4.2"), whole kilometres from
/// 10 up ("343"). Split out so the threshold is testable on its own.
String formatKm(double km) =>
    km < 10 ? km.toStringAsFixed(1) : km.round().toString();
