/// Pure, timezone-safe calendar math: month grid layout (Monday-first, per
/// Polish convention), day-bucketing events (including ones that cross
/// midnight or run all day), and picking the "upcoming" set for the strip
/// under the grid. Same philosophy as `lib/domain/day_math.dart` — every
/// comparison truncates to local year/month/day first so "today" always
/// means today's calendar date.
library;

import 'models/calendar_event.dart';

const _monthAbbr = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Truncates [d] to its local calendar date — no time-of-day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday-first weekday index: Monday=0 … Sunday=6. Dart's
/// [DateTime.weekday] is Monday=1…Sunday=7.
int mondayFirstIndex(DateTime d) => d.weekday - 1;

/// The 42 dates (a fixed 6 Monday-first weeks) making up the visible grid
/// for [year]/[month] — includes trailing days borrowed from the previous
/// month and leading days borrowed from the next one, so every week is a
/// full row and the grid never changes height as the user pages between
/// months (some months only need 5 rows; a 6th is always rendered anyway
/// for that reason).
List<DateTime> monthGridDays(int year, int month) {
  final firstOfMonth = DateTime(year, month, 1);
  final gridStart = firstOfMonth.subtract(
    Duration(days: mondayFirstIndex(firstOfMonth)),
  );
  return List.generate(42, (i) => gridStart.add(Duration(days: i)));
}

/// Whether [day] falls within [year]/[month] itself, as opposed to being a
/// leading/trailing day borrowed from a neighbouring month.
bool isInMonth(DateTime day, int year, int month) =>
    day.year == year && day.month == month;

/// The half-open `[start, end)` range a month-range repository query should
/// ask for — matches the server's `starts >= X && starts < Y` filter shape.
/// Dart's [DateTime] constructor normalizes an out-of-range month (13 →
/// next January), so December rolls into January correctly.
({DateTime start, DateTime end}) monthQueryRange(int year, int month) {
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 1);
  return (start: start, end: end);
}

/// "Aug 2026" — the grid header label. No locale library needed for this
/// one format, same reasoning as `day_math.dart`'s `friendlyDate`.
String monthLabel(int year, int month) => '${_monthAbbr[month - 1]} $year';

/// "19:00" — used for the day-list rows; all-day events skip this.
String timeLabel(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Every date-only day [event] touches, inclusive of both ends. A
/// same-day/point-in-time event covers just its start date. A multi-day
/// event, or one that simply crosses midnight (e.g. 23:00 → 01:00), covers
/// every date from its start date through its end date. A malformed record
/// with an end before its start (shouldn't happen, but the UI shouldn't
/// crash on it either) is treated as covering only its start date.
List<DateTime> daysCoveredByEvent(CalendarEvent event) {
  final startDay = dateOnly(event.starts);
  final endDay = event.ends != null ? dateOnly(event.ends!) : startDay;
  if (endDay.isBefore(startDay)) return [startDay];

  final days = <DateTime>[];
  var d = startDay;
  while (!d.isAfter(endDay)) {
    days.add(d);
    d = d.add(const Duration(days: 1));
  }
  return days;
}

/// Buckets [events] by every date-only day they cover, for the grid's
/// per-cell dots. Only days within `[rangeStart, rangeEnd)` are kept, so a
/// multi-day event that runs past the visible grid doesn't leak dots onto
/// cells the caller never rendered. Each bucket is sorted by start time.
Map<DateTime, List<CalendarEvent>> bucketEventsByDay(
  List<CalendarEvent> events, {
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final buckets = <DateTime, List<CalendarEvent>>{};
  for (final event in events) {
    for (final day in daysCoveredByEvent(event)) {
      if (day.isBefore(rangeStart) || !day.isBefore(rangeEnd)) continue;
      (buckets[day] ??= <CalendarEvent>[]).add(event);
    }
  }
  for (final bucket in buckets.values) {
    bucket.sort((a, b) => a.starts.compareTo(b.starts));
  }
  return buckets;
}

/// The next [limit] upcoming events — "today" counts as upcoming (same
/// "today counts" rule as `CountdownsViewModel.nearestUpcoming`), including
/// a multi-day event that started before today but is still running.
/// Ordered by start time; ties broken by title so the order is stable and
/// testable.
List<CalendarEvent> upcomingEvents(
  List<CalendarEvent> events, {
  required DateTime now,
  int limit = 3,
}) {
  final today = dateOnly(now);
  final upcoming =
      events.where((e) {
          final days = daysCoveredByEvent(e);
          return days.any((d) => !d.isBefore(today));
        }).toList()
        ..sort((a, b) {
          final cmp = a.starts.compareTo(b.starts);
          return cmp != 0 ? cmp : a.title.compareTo(b.title);
        });
  return upcoming.take(limit).toList();
}

/// The first day of [event] that is today or later — what the upcoming
/// strip's "in N days" label is computed from (an ongoing multi-day event
/// counts from today, not from its original start date).
DateTime relevantUpcomingDay(CalendarEvent event, DateTime now) {
  final today = dateOnly(now);
  final days = daysCoveredByEvent(event);
  return days.firstWhere((d) => !d.isBefore(today), orElse: () => today);
}
