import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/utc_offset.dart';

DeviceStatus _device({
  required String kind,
  required DateTime lastSeen,
  String? timezone,
}) => DeviceStatus(
  id: kind,
  ownerId: 'partner',
  name: kind,
  kind: kind,
  lastSeen: lastSeen,
  timezone: timezone,
);

void main() {
  group('UtcOffset.encode/parse', () {
    test('encodes a positive offset', () {
      expect(const UtcOffset(120).encode(), 'UTC+02:00');
    });

    test('encodes a negative offset', () {
      expect(const UtcOffset(-330).encode(), 'UTC-05:30');
    });

    test('encodes zero as UTC+00:00', () {
      expect(const UtcOffset(0).encode(), 'UTC+00:00');
    });

    test('round-trips through encode/parse', () {
      for (final minutes in [0, 60, -60, 330, -330, 720, -720]) {
        final offset = UtcOffset(minutes);
        expect(UtcOffset.parse(offset.encode()), offset);
      }
    });

    test('parse rejects malformed strings', () {
      expect(UtcOffset.parse(null), isNull);
      expect(UtcOffset.parse(''), isNull);
      expect(UtcOffset.parse('Europe/Warsaw'), isNull);
      expect(UtcOffset.parse('UTC+2:00'), isNull);
      expect(UtcOffset.parse('junk'), isNull);
    });

    test('two offsets with the same minutes are equal', () {
      expect(const UtcOffset(120), const UtcOffset(120));
    });
  });

  group('resolvePartnerUtcOffset', () {
    test('picks the freshest device with a parseable timezone', () {
      final older = _device(
        kind: 'phone',
        lastSeen: DateTime.utc(2026, 8, 23, 10),
        timezone: 'UTC+01:00',
      );
      final newer = _device(
        kind: 'desktop',
        lastSeen: DateTime.utc(2026, 8, 23, 11),
        timezone: 'UTC+09:00',
      );

      expect(
        resolvePartnerUtcOffset([older, newer]),
        const UtcOffset(9 * 60),
      );
    });

    test('skips devices with no or unparseable timezone', () {
      final noTz = _device(
        kind: 'phone',
        lastSeen: DateTime.utc(2026, 8, 23, 12),
      );
      final withTz = _device(
        kind: 'desktop',
        lastSeen: DateTime.utc(2026, 8, 23, 9),
        timezone: 'UTC-03:00',
      );

      expect(resolvePartnerUtcOffset([noTz, withTz]), const UtcOffset(-180));
    });

    test('returns null when nothing has a usable timezone', () {
      final device = _device(
        kind: 'phone',
        lastSeen: DateTime.utc(2026, 8, 23, 12),
      );
      expect(resolvePartnerUtcOffset([device]), isNull);
    });

    test('returns null for an empty device list', () {
      expect(resolvePartnerUtcOffset(const []), isNull);
    });
  });

  group('resolveDualClockLine', () {
    test('returns null when both offsets match', () {
      final line = resolveDualClockLine(
        mine: const UtcOffset(60),
        theirs: const UtcOffset(60),
        nowUtc: DateTime.utc(2026, 8, 23, 12, 0),
      );
      expect(line, isNull);
    });

    test('returns null when the partner offset is unknown', () {
      final line = resolveDualClockLine(
        mine: const UtcOffset(60),
        theirs: null,
        nowUtc: DateTime.utc(2026, 8, 23, 12, 0),
      );
      expect(line, isNull);
    });

    test('formats their local time when offsets differ', () {
      // Mine: UTC+1. Theirs: UTC+9. now = 12:00 UTC -> their local 21:00.
      final line = resolveDualClockLine(
        mine: const UtcOffset(60),
        theirs: const UtcOffset(9 * 60),
        nowUtc: DateTime.utc(2026, 8, 23, 12, 0),
      );
      expect(line, contains('21:00'));
      expect(line, contains('☾')); // night glyph at 21:00
    });

    test('uses the day glyph during their daytime hours', () {
      // Mine: UTC+0. Theirs: UTC+9. now = 03:00 UTC -> their local 12:00.
      final line = resolveDualClockLine(
        mine: const UtcOffset(0),
        theirs: const UtcOffset(9 * 60),
        nowUtc: DateTime.utc(2026, 8, 23, 3, 0),
      );
      expect(line, contains('12:00'));
      expect(line, contains('☀'));
    });

    test('handles a negative-offset partner correctly', () {
      // Mine: UTC+1. Theirs: UTC-5. now = 12:00 UTC -> their local 07:00.
      final line = resolveDualClockLine(
        mine: const UtcOffset(60),
        theirs: const UtcOffset(-5 * 60),
        nowUtc: DateTime.utc(2026, 8, 23, 12, 0),
      );
      expect(line, contains('07:00'));
    });
  });
}
