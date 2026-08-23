import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/location_repository.dart';
import 'package:couples_app/domain/models/ghost_state.dart';

/// A `locations` row shaped exactly like the one kb/contracts.md describes
/// (route-created, `recorded` from OwnTracks' `tst`).
RecordModel _locationRecord(Map<String, dynamic> overrides) => RecordModel({
  'id': 'loc1',
  'collectionId': 'c',
  'collectionName': 'locations',
  'user': 'them',
  'lat': 52.2297,
  'lon': 21.0122,
  'accuracy': 12,
  'battery': 64,
  'velocity': 4.5,
  'recorded': '2026-08-23 12:00:00.000Z',
  ...overrides,
});

void main() {
  group('pointFromRecord', () {
    test('maps every contract field', () {
      final point = LocationRepository.pointFromRecord(_locationRecord({}));

      expect(point.id, 'loc1');
      expect(point.userId, 'them');
      expect(point.lat, 52.2297);
      expect(point.lon, 21.0122);
      expect(point.accuracy, 12);
      expect(point.battery, 64);
      expect(point.velocity, 4.5);
      expect(point.recorded.toUtc(), DateTime.utc(2026, 8, 23, 12));
      // Everything user-facing measures against local time.
      expect(point.recorded.isUtc, isFalse);
    });

    test('integer lat/lon from JSON still land as doubles', () {
      final point = LocationRepository.pointFromRecord(
        _locationRecord({'lat': 52, 'lon': 21}),
      );
      expect(point.lat, 52.0);
      expect(point.lon, 21.0);
    });

    test('unreported accuracy/battery read as unknown, not as zero', () {
      // A PocketBase NumberField stores 0 both for "zero" and for "never
      // set" — same trap DeviceRepository's battery handling documents.
      final point = LocationRepository.pointFromRecord(
        _locationRecord({'accuracy': 0, 'battery': 0}),
      );
      expect(point.accuracy, isNull);
      expect(point.battery, isNull);
    });

    test('missing optional fields do not blow up', () {
      final point = LocationRepository.pointFromRecord(
        RecordModel({'id': 'loc2', 'user': 'me', 'lat': 1.5, 'lon': 2.5}),
      );
      expect(point.accuracy, isNull);
      expect(point.battery, isNull);
      // No `recorded` at all is treated as ancient, so the 24h staleness
      // rule hides it rather than pretending it's current.
      expect(point.recorded, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('an unparseable recorded date is ancient, not "now"', () {
      final point = LocationRepository.pointFromRecord(
        _locationRecord({'recorded': 'nonsense'}),
      );
      expect(point.recorded, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('ageAt measures from the fix time, not from storage', () {
      final point = LocationRepository.pointFromRecord(_locationRecord({}));
      expect(
        point.ageAt(point.recorded.add(const Duration(minutes: 7))),
        const Duration(minutes: 7),
      );
    });

    test('two mappings of the same row are equal (marker diffing relies on it)',
        () {
      expect(
        LocationRepository.pointFromRecord(_locationRecord({})),
        LocationRepository.pointFromRecord(_locationRecord({})),
      );
      expect(
        LocationRepository.pointFromRecord(_locationRecord({})),
        isNot(LocationRepository.pointFromRecord(_locationRecord({'lat': 1}))),
      );
    });
  });

  group('ghostUntilFromRecord', () {
    RecordModel user(Map<String, dynamic> data) =>
        RecordModel({'id': 'them', 'name': 'mati', ...data});

    test('reads a set ghost_until', () {
      final until = LocationRepository.ghostUntilFromRecord(
        user({'ghost_until': '2026-08-23 18:00:00.000Z'}),
      );
      expect(until?.toUtc(), DateTime.utc(2026, 8, 23, 18));
    });

    test('an empty ghost_until is "not paused"', () {
      expect(
        LocationRepository.ghostUntilFromRecord(user({'ghost_until': ''})),
        isNull,
      );
    });

    test('a users record without the field yet is "not paused"', () {
      // The phase-3 migration may not have landed on the server; the app
      // must not treat that as an error.
      expect(LocationRepository.ghostUntilFromRecord(user({})), isNull);
      expect(
        resolveGhostState(LocationRepository.ghostUntilFromRecord(user({}))),
        GhostState.off,
      );
    });

    test('the sentinel round-trips to an indefinite pause', () {
      final record = user({
        'ghost_until': indefiniteGhostUntil.toIso8601String(),
      });
      final state = resolveGhostState(
        LocationRepository.ghostUntilFromRecord(record),
      );
      expect(state.kind, GhostKind.indefinite);
    });
  });
}
