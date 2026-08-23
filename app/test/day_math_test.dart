import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/day_math.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';

void main() {
  group('daysBetweenDates / daysUntil', () {
    test('same calendar date -> 0, even with different times of day', () {
      final morning = DateTime(2026, 8, 23, 6);
      final night = DateTime(2026, 8, 23, 23, 59);
      expect(daysBetweenDates(morning, night), 0);
      expect(daysUntil(night, now: morning), 0);
    });

    test('a date tomorrow -> 1, regardless of hour-of-day gap', () {
      final now = DateTime(2026, 8, 23, 23);
      final target = DateTime(2026, 8, 24, 0, 30);
      expect(daysUntil(target, now: now), 1);
    });

    test('a date yesterday -> -1', () {
      final now = DateTime(2026, 8, 23, 0, 30);
      final target = DateTime(2026, 8, 22, 23);
      expect(daysUntil(target, now: now), -1);
    });

    test('a date N days in the future -> N', () {
      final now = DateTime(2026, 8, 23);
      final target = DateTime(2026, 10, 4); // 42 days later
      expect(daysUntil(target, now: now), 42);
    });

    test('a date N days in the past -> -N', () {
      final now = DateTime(2026, 8, 23);
      final target = DateTime(2026, 7, 1);
      expect(daysUntil(target, now: now), -53);
    });

    test('crosses a year boundary correctly', () {
      final now = DateTime(2026, 12, 30);
      final target = DateTime(2027, 1, 2);
      expect(daysUntil(target, now: now), 3);
    });
  });

  group('countdownDayLabel', () {
    test('today -> the special "today!!" label', () {
      expect(countdownDayLabel(0), AppStrings.countdownToday);
    });

    test('future -> "in N days" (pluralized)', () {
      expect(countdownDayLabel(1), 'in 1 day');
      expect(countdownDayLabel(42), 'in 42 days');
    });

    test('past -> "N days ago" (pluralized)', () {
      expect(countdownDayLabel(-1), '1 day ago');
      expect(countdownDayLabel(-10), '10 days ago');
    });
  });

  group('daysTogether', () {
    test('counts whole days since the anniversary date', () {
      final anniversary = DateTime(2020, 1, 1);
      final now = DateTime(2020, 1, 11);
      expect(daysTogether(anniversary, now: now), 10);
    });

    test('same day -> 0', () {
      final today = DateTime(2026, 8, 23);
      expect(daysTogether(today, now: today), 0);
    });

    test(
      'an anniversary mistakenly set in the future clamps to 0, not negative',
      () {
        final anniversary = DateTime(2027, 1, 1);
        final now = DateTime(2026, 8, 23);
        expect(daysTogether(anniversary, now: now), 0);
      },
    );
  });

  group('friendlyDate', () {
    test('formats as "D Mon YYYY"', () {
      expect(friendlyDate(DateTime(2026, 12, 24)), '24 Dec 2026');
      expect(friendlyDate(DateTime(2026, 1, 5)), '5 Jan 2026');
    });
  });
}
