import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/calendar_math.dart';
import 'package:couples_app/domain/models/calendar_event.dart';
import 'package:couples_app/domain/models/event_color.dart';

CalendarEvent _event({
  String id = 'e1',
  String title = 'event',
  required DateTime starts,
  DateTime? ends,
  bool allDay = false,
  EventColor color = EventColor.pink,
}) => CalendarEvent(
  id: id,
  coupleId: 'c1',
  title: title,
  starts: starts,
  ends: ends,
  allDay: allDay,
  color: color,
);

void main() {
  group('mondayFirstIndex', () {
    test('Monday -> 0 … Sunday -> 6', () {
      // 2026-08-17 is a Monday.
      expect(mondayFirstIndex(DateTime(2026, 8, 17)), 0);
      expect(mondayFirstIndex(DateTime(2026, 8, 18)), 1); // Tue
      expect(mondayFirstIndex(DateTime(2026, 8, 22)), 5); // Sat
      expect(mondayFirstIndex(DateTime(2026, 8, 23)), 6); // Sun
    });
  });

  group('monthGridDays', () {
    test('always exactly 42 Monday-first cells', () {
      expect(monthGridDays(2026, 8).length, 42);
      expect(monthGridDays(2026, 2).length, 42);
    });

    test('every row starts on a Monday', () {
      final days = monthGridDays(2026, 8);
      for (var row = 0; row < 6; row++) {
        expect(days[row * 7].weekday, DateTime.monday);
      }
    });

    test('August 2026 (starts on a Saturday) borrows 5 leading days from '
        'July and pads with August', () {
      final days = monthGridDays(2026, 8);
      // Aug 1 2026 is a Saturday -> the grid's Monday start is 2026-07-27.
      expect(days.first, DateTime(2026, 7, 27));
      expect(days[5], DateTime(2026, 8, 1));
      expect(isInMonth(days[5], 2026, 8), isTrue);
      expect(isInMonth(days.first, 2026, 8), isFalse);
    });

    test('a month that starts on a Monday needs no leading days', () {
      // 2026-06-01 is a Monday.
      final days = monthGridDays(2026, 6);
      expect(days.first, DateTime(2026, 6, 1));
    });

    test('leap year February 2028 renders all 29 days inside the grid', () {
      final days = monthGridDays(2028, 2);
      final inMonth = days.where((d) => isInMonth(d, 2028, 2)).toList();
      expect(inMonth.length, 29);
      expect(inMonth.last, DateTime(2028, 2, 29));
    });

    test('non-leap year February 2026 has only 28 in-month days', () {
      final days = monthGridDays(2026, 2);
      final inMonth = days.where((d) => isInMonth(d, 2026, 2)).toList();
      expect(inMonth.length, 28);
    });

    test('December rolls forward into January on the grid\'s trailing days', () {
      final days = monthGridDays(2026, 12);
      expect(days.last.isAfter(DateTime(2026, 12, 31)), isTrue);
      expect(days.last.year, 2027);
      expect(days.last.month, 1);
    });
  });

  group('monthQueryRange', () {
    test('half-open [start, end) spanning exactly the month', () {
      final range = monthQueryRange(2026, 8);
      expect(range.start, DateTime(2026, 8, 1));
      expect(range.end, DateTime(2026, 9, 1));
    });

    test('December wraps into next January', () {
      final range = monthQueryRange(2026, 12);
      expect(range.start, DateTime(2026, 12, 1));
      expect(range.end, DateTime(2027, 1, 1));
    });
  });

  group('monthLabel', () {
    test('formats as "Mon YYYY"', () {
      expect(monthLabel(2026, 8), 'Aug 2026');
      expect(monthLabel(2027, 1), 'Jan 2027');
    });
  });

  group('timeLabel', () {
    test('zero-pads hour and minute', () {
      expect(timeLabel(DateTime(2026, 8, 23, 9, 5)), '09:05');
      expect(timeLabel(DateTime(2026, 8, 23, 19, 0)), '19:00');
    });
  });

  group('daysCoveredByEvent', () {
    test('a point-in-time event covers just its start date', () {
      final e = _event(starts: DateTime(2026, 8, 23, 19));
      expect(daysCoveredByEvent(e), [DateTime(2026, 8, 23)]);
    });

    test('an event that crosses midnight covers both calendar dates', () {
      final e = _event(
        starts: DateTime(2026, 8, 23, 23),
        ends: DateTime(2026, 8, 24, 1),
      );
      expect(daysCoveredByEvent(e), [DateTime(2026, 8, 23), DateTime(2026, 8, 24)]);
    });

    test('a multi-day all-day event covers every date in between', () {
      final e = _event(
        starts: DateTime(2026, 8, 20),
        ends: DateTime(2026, 8, 23),
        allDay: true,
      );
      expect(daysCoveredByEvent(e), [
        DateTime(2026, 8, 20),
        DateTime(2026, 8, 21),
        DateTime(2026, 8, 22),
        DateTime(2026, 8, 23),
      ]);
    });

    test('an all-day event with no end covers just its start date', () {
      final e = _event(starts: DateTime(2026, 8, 23), allDay: true);
      expect(daysCoveredByEvent(e), [DateTime(2026, 8, 23)]);
    });

    test('a malformed end before the start is ignored, not a crash', () {
      final e = _event(
        starts: DateTime(2026, 8, 23),
        ends: DateTime(2026, 8, 20),
      );
      expect(daysCoveredByEvent(e), [DateTime(2026, 8, 23)]);
    });
  });

  group('bucketEventsByDay', () {
    test('buckets a same-day event under its one day', () {
      final e = _event(starts: DateTime(2026, 8, 23, 19));
      final buckets = bucketEventsByDay(
        [e],
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 1),
      );
      expect(buckets[DateTime(2026, 8, 23)], [e]);
    });

    test('a cross-midnight event shows up on both its days', () {
      final e = _event(
        starts: DateTime(2026, 8, 23, 23),
        ends: DateTime(2026, 8, 24, 1),
      );
      final buckets = bucketEventsByDay(
        [e],
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 1),
      );
      expect(buckets[DateTime(2026, 8, 23)], [e]);
      expect(buckets[DateTime(2026, 8, 24)], [e]);
    });

    test('days outside [rangeStart, rangeEnd) are dropped', () {
      final e = _event(
        starts: DateTime(2026, 7, 30),
        ends: DateTime(2026, 8, 2),
      );
      final buckets = bucketEventsByDay(
        [e],
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 1),
      );
      expect(buckets.containsKey(DateTime(2026, 7, 30)), isFalse);
      expect(buckets.containsKey(DateTime(2026, 7, 31)), isFalse);
      expect(buckets[DateTime(2026, 8, 1)], [e]);
      expect(buckets[DateTime(2026, 8, 2)], [e]);
    });

    test('a day bucket is sorted by start time', () {
      final late = _event(id: 'late', title: 'late', starts: DateTime(2026, 8, 23, 20));
      final early = _event(id: 'early', title: 'early', starts: DateTime(2026, 8, 23, 8));
      final buckets = bucketEventsByDay(
        [late, early],
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 9, 1),
      );
      expect(buckets[DateTime(2026, 8, 23)], [early, late]);
    });
  });

  group('upcomingEvents', () {
    final now = DateTime(2026, 8, 23);

    test('today counts as upcoming', () {
      final today = _event(starts: DateTime(2026, 8, 23, 10));
      expect(upcomingEvents([today], now: now), [today]);
    });

    test('past events are excluded', () {
      final past = _event(starts: DateTime(2026, 8, 20));
      expect(upcomingEvents([past], now: now), isEmpty);
    });

    test('an ongoing multi-day event counts even if it started in the past', () {
      final ongoing = _event(
        starts: DateTime(2026, 8, 20),
        ends: DateTime(2026, 8, 25),
      );
      expect(upcomingEvents([ongoing], now: now), [ongoing]);
    });

    test('sorted by start time, limited to `limit`', () {
      final d1 = _event(id: '1', title: 'a', starts: DateTime(2026, 8, 25));
      final d2 = _event(id: '2', title: 'b', starts: DateTime(2026, 8, 24));
      final d3 = _event(id: '3', title: 'c', starts: DateTime(2026, 8, 23));
      final d4 = _event(id: '4', title: 'd', starts: DateTime(2026, 8, 26));
      final result = upcomingEvents([d1, d2, d3, d4], now: now, limit: 3);
      expect(result.map((e) => e.id), ['3', '2', '1']);
    });

    test('ties on start time break by title', () {
      final b = _event(id: 'b', title: 'zebra', starts: DateTime(2026, 8, 23, 9));
      final a = _event(id: 'a', title: 'apple', starts: DateTime(2026, 8, 23, 9));
      final result = upcomingEvents([b, a], now: now);
      expect(result.map((e) => e.id), ['a', 'b']);
    });
  });

  group('relevantUpcomingDay', () {
    test('a future event -> its own start date', () {
      final e = _event(starts: DateTime(2026, 8, 26));
      expect(
        relevantUpcomingDay(e, DateTime(2026, 8, 23)),
        DateTime(2026, 8, 26),
      );
    });

    test('an ongoing multi-day event -> today, not its original start', () {
      final e = _event(
        starts: DateTime(2026, 8, 20),
        ends: DateTime(2026, 8, 25),
      );
      expect(
        relevantUpcomingDay(e, DateTime(2026, 8, 23)),
        DateTime(2026, 8, 23),
      );
    });
  });
}
