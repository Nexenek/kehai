import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/thumbkiss/thumb_kiss_logic.dart';

void main() {
  group('shouldSendTouch', () {
    test('always sends the first point of a press (null lastSentAt)', () {
      expect(
        shouldSendTouch(lastSentAt: null, now: DateTime.utc(2026, 1, 1)),
        isTrue,
      );
    });

    test('withholds a send inside the throttle window', () {
      final last = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final now = last.add(const Duration(milliseconds: 100));
      expect(shouldSendTouch(lastSentAt: last, now: now), isFalse);
    });

    test('allows a send once the throttle interval has elapsed', () {
      final last = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final now = last.add(touchSendInterval);
      expect(shouldSendTouch(lastSentAt: last, now: now), isTrue);
    });

    test('allows a send well past the throttle interval', () {
      final last = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final now = last.add(const Duration(seconds: 5));
      expect(shouldSendTouch(lastSentAt: last, now: now), isTrue);
    });
  });

  group('isTouchFresh', () {
    test('a point from right now is fresh', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(isTouchFresh(now, now), isTrue);
    });

    test('a point just under the freshness window is fresh', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final now = at.add(touchFreshWindow - const Duration(milliseconds: 1));
      expect(isTouchFresh(at, now), isTrue);
    });

    test('a point past the freshness window is stale', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final now = at.add(touchFreshWindow + const Duration(milliseconds: 1));
      expect(isTouchFresh(at, now), isFalse);
    });
  });

  group('touchDistance', () {
    test('zero distance for identical points', () {
      expect(touchDistance(const Offset(0.5, 0.5), const Offset(0.5, 0.5)), 0);
    });

    test('computes straight-line distance', () {
      // 3-4-5 triangle scaled by 0.1 -> distance 0.5.
      final d = touchDistance(const Offset(0, 0), const Offset(0.3, 0.4));
      expect(d, closeTo(0.5, 1e-9));
    });
  });

  group('didMeet', () {
    final now = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('false when either point is missing', () {
      expect(
        didMeet(
          mine: null,
          mineAt: now,
          theirs: const Offset(0.5, 0.5),
          theirsAt: now,
          now: now,
        ),
        isFalse,
      );
      expect(
        didMeet(
          mine: const Offset(0.5, 0.5),
          mineAt: now,
          theirs: null,
          theirsAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('true when close together and both fresh', () {
      expect(
        didMeet(
          mine: const Offset(0.50, 0.50),
          mineAt: now,
          theirs: const Offset(0.55, 0.50),
          theirsAt: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('false when farther apart than the met threshold', () {
      expect(
        didMeet(
          mine: const Offset(0.1, 0.1),
          mineAt: now,
          theirs: const Offset(0.9, 0.9),
          theirsAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('just inside the threshold counts as met', () {
      final theirs = Offset(0.5 + metDistanceThreshold - 0.001, 0.5);
      expect(
        didMeet(
          mine: const Offset(0.5, 0.5),
          mineAt: now,
          theirs: theirs,
          theirsAt: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('just outside the threshold does not count as met', () {
      final theirs = Offset(0.5 + metDistanceThreshold + 0.001, 0.5);
      expect(
        didMeet(
          mine: const Offset(0.5, 0.5),
          mineAt: now,
          theirs: theirs,
          theirsAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('false when close but my point is stale', () {
      final staleAt = now.subtract(
        touchFreshWindow + const Duration(milliseconds: 1),
      );
      expect(
        didMeet(
          mine: const Offset(0.5, 0.5),
          mineAt: staleAt,
          theirs: const Offset(0.5, 0.5),
          theirsAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('false when close but their point is stale', () {
      final staleAt = now.subtract(
        touchFreshWindow + const Duration(milliseconds: 1),
      );
      expect(
        didMeet(
          mine: const Offset(0.5, 0.5),
          mineAt: now,
          theirs: const Offset(0.5, 0.5),
          theirsAt: staleAt,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
