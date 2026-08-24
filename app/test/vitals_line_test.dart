import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/heart_rate_sample.dart';
import 'package:couples_app/domain/models/vitals_line.dart';

DeviceStatus _phone({
  DateTime? lastSeen,
  int? stepsToday,
  HeartRateSample? heartRate,
  String kind = 'phone',
  String id = 'd1',
}) => DeviceStatus(
  id: id,
  ownerId: 'partner',
  name: 'phone',
  kind: kind,
  lastSeen: lastSeen ?? DateTime.utc(2026, 8, 24, 12),
  stepsToday: stepsToday,
  heartRate: heartRate,
);

void main() {
  final now = DateTime.utc(2026, 8, 24, 12);

  group('resolvePartnerVitals', () {
    test('nothing without any devices', () {
      final vitals = resolvePartnerVitals(const [], nowUtc: now);
      expect(vitals, PartnerVitals.none);
      expect(vitals.isEmpty, isTrue);
    });

    test('nothing when the only device is not a phone', () {
      final desktop = _phone(
        kind: 'desktop',
        heartRate: HeartRateSample(bpm: 72, at: now),
        stepsToday: 4231,
      );
      final vitals = resolvePartnerVitals([desktop], nowUtc: now);
      expect(vitals.isEmpty, isTrue);
    });

    test('a fresh heart-rate sample shows bpm', () {
      final phone = _phone(
        heartRate: HeartRateSample(bpm: 72, at: now.subtract(const Duration(minutes: 10))),
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.bpm, 72);
    });

    test('a sample right at the edge of freshWindow still counts', () {
      final phone = _phone(
        heartRate: HeartRateSample(bpm: 72, at: now.subtract(HeartRateSample.freshWindow)),
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.bpm, 72);
    });

    test('a stale heart-rate sample hides bpm entirely', () {
      final phone = _phone(
        heartRate: HeartRateSample(
          bpm: 72,
          at: now.subtract(HeartRateSample.freshWindow + const Duration(minutes: 1)),
        ),
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.bpm, isNull);
    });

    test('steps show when the phone was seen within the last 2 hours', () {
      final phone = _phone(
        lastSeen: now.subtract(const Duration(hours: 1)),
        stepsToday: 4231,
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.stepsToday, 4231);
    });

    test('steps right at the edge of the 2h window still count', () {
      final phone = _phone(
        lastSeen: now.subtract(stepsFreshWindow),
        stepsToday: 4231,
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.stepsToday, 4231);
    });

    test('steps hide once the phone has not been seen in over 2 hours', () {
      final phone = _phone(
        lastSeen: now.subtract(stepsFreshWindow + const Duration(minutes: 1)),
        stepsToday: 4231,
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.stepsToday, isNull);
    });

    test('steps and bpm are independent — one can be fresh while the other '
        'is stale', () {
      final phone = _phone(
        lastSeen: now.subtract(stepsFreshWindow + const Duration(minutes: 1)),
        stepsToday: 4231,
        heartRate: HeartRateSample(bpm: 72, at: now.subtract(const Duration(minutes: 5))),
      );
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.bpm, 72);
      expect(vitals.stepsToday, isNull);
    });

    test('no bpm, no steps, no report at all => isEmpty', () {
      final phone = _phone();
      final vitals = resolvePartnerVitals([phone], nowUtc: now);
      expect(vitals.isEmpty, isTrue);
    });

    test('picks the most-recently-seen phone when there is more than one', () {
      final older = _phone(
        id: 'old',
        lastSeen: now.subtract(const Duration(hours: 3)),
        heartRate: HeartRateSample(bpm: 60, at: now),
      );
      final newer = _phone(
        id: 'new',
        lastSeen: now.subtract(const Duration(minutes: 1)),
        heartRate: HeartRateSample(bpm: 90, at: now),
      );
      final vitals = resolvePartnerVitals([older, newer], nowUtc: now);
      expect(vitals.bpm, 90);
    });
  });
}
