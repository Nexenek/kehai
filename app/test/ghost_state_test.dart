import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ghost_state.dart';

void main() {
  final now = DateTime(2026, 8, 23, 14, 30);

  group('parseGhostUntil', () {
    test('empty, missing and unparseable all mean "not paused"', () {
      expect(parseGhostUntil(null), isNull);
      expect(parseGhostUntil(''), isNull);
      expect(parseGhostUntil('not a date'), isNull);
    });

    test("PocketBase's space-separated UTC format parses, and localizes", () {
      final parsed = parseGhostUntil('2026-08-23 18:00:00.000Z');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
      expect(
        parsed.toUtc(),
        DateTime.utc(2026, 8, 23, 18),
      );
    });
  });

  group('resolveGhostState', () {
    test('no field set is off', () {
      expect(resolveGhostState(null, now: now), GhostState.off);
      expect(resolveGhostState(null, now: now).isActive, isFalse);
    });

    test('a ghost_until in the past has simply expired', () {
      final past = now.subtract(const Duration(minutes: 1));
      expect(resolveGhostState(past, now: now), GhostState.off);
    });

    test('exactly now is over too — the server stops dropping at that tick', () {
      expect(resolveGhostState(now, now: now), GhostState.off);
    });

    test('a future ghost_until is a timed pause, and keeps its deadline', () {
      final until = now.add(const Duration(hours: 1));
      final state = resolveGhostState(until, now: now);
      expect(state.kind, GhostKind.until);
      expect(state.until, until);
      expect(state.isActive, isTrue);
    });

    test('the year-2100 sentinel reads back as indefinite, not as a date', () {
      final state = resolveGhostState(indefiniteGhostUntil, now: now);
      expect(state.kind, GhostKind.indefinite);
      expect(state.isActive, isTrue);
    });

    test('a far-future date past the sentinel year is indefinite as well', () {
      final state = resolveGhostState(DateTime.utc(2200), now: now);
      expect(state.kind, GhostKind.indefinite);
    });

    test('the year is judged in UTC, so a local new-year edge is stable', () {
      // 2099-12-31 23:30 UTC is already 2100 in some local zones (and vice
      // versa). The sentinel is written in UTC, so it is read in UTC.
      final state = resolveGhostState(
        DateTime.utc(2099, 12, 31, 23, 30),
        now: now,
      );
      expect(state.kind, GhostKind.until);
    });
  });

  group('ghostUntilFor', () {
    test('no option clears the field', () {
      expect(ghostUntilFor(null, now: now), isNull);
    });

    test('1h is exactly an hour out', () {
      expect(
        ghostUntilFor(GhostOption.hour, now: now),
        DateTime(2026, 8, 23, 15, 30),
      );
    });

    test('"until tomorrow" is tomorrow at 08:00 local, as the label says', () {
      expect(
        ghostUntilFor(GhostOption.untilTomorrow, now: now),
        DateTime(2026, 8, 24, 8),
      );
    });

    test('"until tomorrow" late at night is still the next morning', () {
      expect(
        ghostUntilFor(
          GhostOption.untilTomorrow,
          now: DateTime(2026, 8, 23, 23, 55),
        ),
        DateTime(2026, 8, 24, 8),
      );
    });

    test('"until tomorrow" rolls over month and year ends', () {
      expect(
        ghostUntilFor(
          GhostOption.untilTomorrow,
          now: DateTime(2026, 12, 31, 20),
        ),
        DateTime(2027, 1, 1, 8),
      );
      expect(
        ghostUntilFor(GhostOption.untilTomorrow, now: DateTime(2026, 8, 31, 9)),
        DateTime(2026, 9, 1, 8),
      );
    });

    test('indefinite writes the sentinel, which resolves back to indefinite', () {
      final until = ghostUntilFor(GhostOption.indefinite, now: now);
      expect(until, indefiniteGhostUntil);
      expect(resolveGhostState(until, now: now).kind, GhostKind.indefinite);
    });

    test('every option round-trips through resolveGhostState as active', () {
      for (final option in GhostOption.values) {
        final state = resolveGhostState(
          ghostUntilFor(option, now: now),
          now: now,
        );
        expect(state.isActive, isTrue, reason: '$option should be a pause');
      }
    });
  });

  group('formatGhostUntil', () {
    test('later today is just the clock time', () {
      expect(formatGhostUntil(DateTime(2026, 8, 23, 15, 30), now: now), '15:30');
    });

    test('minutes are zero-padded, hours are not', () {
      expect(formatGhostUntil(DateTime(2026, 8, 23, 9, 5), now: now), '9:05');
    });

    test('the next calendar day says "tomorrow"', () {
      expect(
        formatGhostUntil(DateTime(2026, 8, 24, 8), now: now),
        'tomorrow 8:00',
      );
    });

    test('further out spells the day out', () {
      expect(
        formatGhostUntil(DateTime(2026, 8, 26, 8), now: now),
        '26 aug, 8:00',
      );
    });
  });
}
