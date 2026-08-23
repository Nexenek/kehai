import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/location_math.dart';
import 'package:couples_app/domain/models/ghost_state.dart';
import 'package:couples_app/domain/models/location_point.dart';

LocationPoint _point({
  String userId = 'me',
  double lat = 52.2297,
  double lon = 21.0122,
  required DateTime recorded,
}) => LocationPoint(
  id: '$userId-${recorded.millisecondsSinceEpoch}',
  userId: userId,
  lat: lat,
  lon: lon,
  recorded: recorded,
);

void main() {
  final now = DateTime(2026, 8, 23, 14, 30);

  group('haversineKm', () {
    test('the same point is zero apart', () {
      expect(
        haversineKm(lat1: 52.2297, lon1: 21.0122, lat2: 52.2297, lon2: 21.0122),
        0,
      );
    });

    test('London → Paris is ~343 km', () {
      final km = haversineKm(
        lat1: 51.5007,
        lon1: -0.1246,
        lat2: 48.8567,
        lon2: 2.3508,
      );
      expect(km, closeTo(343.5, 1.5));
    });

    test('Warszawa → Kraków is ~252 km', () {
      final km = haversineKm(
        lat1: 52.2297,
        lon1: 21.0122,
        lat2: 50.0647,
        lon2: 19.9450,
      );
      expect(km, closeTo(252, 2));
    });

    test('one degree of longitude on the equator is ~111.2 km', () {
      expect(haversineKm(lat1: 0, lon1: 0, lat2: 0, lon2: 1), closeTo(111.2, 0.1));
    });

    test('one degree of latitude is ~111.2 km anywhere', () {
      expect(haversineKm(lat1: 0, lon1: 0, lat2: 1, lon2: 0), closeTo(111.2, 0.1));
      expect(
        haversineKm(lat1: 60, lon1: 30, lat2: 61, lon2: 30),
        closeTo(111.2, 0.1),
      );
    });

    test('longitude shrinks with latitude — 1° at 60°N is half the equator', () {
      expect(
        haversineKm(lat1: 60, lon1: 0, lat2: 60, lon2: 1),
        closeTo(55.6, 0.2),
      );
    });

    test('antipodal points are half the circumference, with no NaN', () {
      final km = haversineKm(lat1: 0, lon1: 0, lat2: 0, lon2: 180);
      expect(km.isNaN, isFalse);
      expect(km, closeTo(20015, 5));
    });

    test('it is symmetric', () {
      final there = haversineKm(lat1: 52.2, lon1: 21.0, lat2: 50.0, lon2: 19.9);
      final back = haversineKm(lat1: 50.0, lon1: 19.9, lat2: 52.2, lon2: 21.0);
      expect(there, closeTo(back, 1e-9));
    });

    test('it crosses the antimeridian the short way', () {
      // 1° apart, either side of the date line — not 359°.
      expect(
        haversineKm(lat1: 0, lon1: 179.5, lat2: 0, lon2: -179.5),
        closeTo(111.2, 0.2),
      );
    });
  });

  group('formatKm', () {
    test('under 10 km keeps one decimal', () {
      expect(formatKm(4.23), '4.2');
      expect(formatKm(0.15), '0.1');
      expect(formatKm(9.94), '9.9');
    });

    test('from 10 km up it is whole kilometres', () {
      expect(formatKm(10), '10');
      expect(formatKm(10.4), '10');
      expect(formatKm(343.47), '343');
    });
  });

  group('formatDistanceApart', () {
    LocationPoint mine({Duration age = Duration.zero}) =>
        _point(userId: 'me', recorded: now.subtract(age));

    LocationPoint theirs({
      Duration age = Duration.zero,
      double lat = 50.0647,
      double lon = 19.9450,
    }) => _point(
      userId: 'them',
      lat: lat,
      lon: lon,
      recorded: now.subtract(age),
    );

    test('two fresh points give the contract line', () {
      expect(
        formatDistanceApart(mine: mine(), theirs: theirs(), now: now),
        '~252 km apart ♡\uFE0E',
      );
    });

    test('under 10 km shows one decimal', () {
      final line = formatDistanceApart(
        mine: mine(),
        // ~0.09° of latitude north — a touch over 10 km would round; this
        // is comfortably inside the one-decimal band.
        theirs: theirs(lat: 52.2697, lon: 21.0122),
        now: now,
      );
      expect(line, matches(r'^~\d\.\d km apart ♡\uFE0E$'));
    });

    test('inside GPS noise it stops calling it "apart"', () {
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(lat: 52.2297, lon: 21.0124),
          now: now,
        ),
        'right here together ♡\uFE0E',
      );
    });

    test('a missing point on either side hides the line', () {
      expect(
        formatDistanceApart(mine: null, theirs: theirs(), now: now),
        isNull,
      );
      expect(formatDistanceApart(mine: mine(), theirs: null, now: now), isNull);
      expect(formatDistanceApart(mine: null, theirs: null, now: now), isNull);
    });

    test('either point older than 24h hides the line', () {
      expect(
        formatDistanceApart(
          mine: mine(age: const Duration(hours: 24, minutes: 1)),
          theirs: theirs(),
          now: now,
        ),
        isNull,
      );
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(age: const Duration(hours: 24, minutes: 1)),
          now: now,
        ),
        isNull,
      );
    });

    test('exactly 24h old still counts — the cutoff is "older than"', () {
      expect(
        formatDistanceApart(
          mine: mine(age: stalePointAge),
          theirs: theirs(age: stalePointAge),
          now: now,
        ),
        isNotNull,
      );
    });

    test('a paused partner with a stale point hides the line', () {
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(age: const Duration(hours: 2)),
          partnerGhost: GhostState.until(now.add(const Duration(hours: 1))),
          now: now,
        ),
        isNull,
      );
    });

    test('a paused partner whose point is still fresh keeps the line', () {
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(age: const Duration(minutes: 2)),
          partnerGhost: GhostState.until(now.add(const Duration(hours: 1))),
          now: now,
        ),
        '~252 km apart ♡\uFE0E',
      );
    });

    test('an indefinite pause hides it just the same', () {
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(age: const Duration(hours: 3)),
          partnerGhost: GhostState.indefinite(indefiniteGhostUntil),
          now: now,
        ),
        isNull,
      );
    });

    test('an expired pause is no pause at all', () {
      expect(
        formatDistanceApart(
          mine: mine(),
          theirs: theirs(age: const Duration(hours: 3)),
          partnerGhost: resolveGhostState(
            now.subtract(const Duration(minutes: 5)),
            now: now,
          ),
          now: now,
        ),
        '~252 km apart ♡\uFE0E',
      );
    });

    test('my own pause hides it too, once my point goes stale', () {
      expect(
        formatDistanceApart(
          mine: mine(age: const Duration(hours: 2)),
          theirs: theirs(),
          myGhost: GhostState.until(now.add(const Duration(hours: 1))),
          now: now,
        ),
        isNull,
      );
    });
  });
}
