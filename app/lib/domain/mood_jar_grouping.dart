/// Pure day-bucketing for the mood jar's recent list. Split out from the
/// view model (rather than inlined) so "which calendar day does this land
/// in, relative to now" is unit-testable without a widget tree — same
/// reasoning as `day_math.dart` for countdowns, just per-entry instead of
/// per-countdown.
library;

import 'models/mood_entry.dart';

/// What a [JarDayGroup] is, relative to [now]'s calendar date — the window
/// turns this into AppStrings.jarDayToday / jarDayYesterday / a short date
/// it formats itself (this layer stays UI-string-free).
enum JarDayKind { today, yesterday, older }

/// One calendar day's worth of beads, newest day first, entries within the
/// day kept in whatever order they arrived in (the repository sorts
/// `-created` and the view model prepends realtime arrivals, so callers
/// that feed already-newest-first lists get newest-first rows for free).
class JarDayGroup {
  const JarDayGroup({
    required this.day,
    required this.kind,
    required this.entries,
  });

  /// Date-only (time-of-day truncated to midnight), local.
  final DateTime day;
  final JarDayKind kind;
  final List<MoodEntry> entries;
}

/// Buckets [entries] by local calendar day and sorts the buckets
/// newest-day-first. [now] decides which buckets count as today/yesterday
/// — always pass `clock.now()`, never `DateTime.now()` (this app's clock
/// convention; see thumb_kiss_view_model.dart for the same rule).
List<JarDayGroup> groupMoodEntriesByDay(
  List<MoodEntry> entries, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final byDay = <DateTime, List<MoodEntry>>{};
  for (final entry in entries) {
    final c = entry.created;
    final day = DateTime(c.year, c.month, c.day);
    (byDay[day] ??= []).add(entry);
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      JarDayGroup(
        day: day,
        kind: day == today
            ? JarDayKind.today
            : day == yesterday
            ? JarDayKind.yesterday
            : JarDayKind.older,
        entries: byDay[day]!,
      ),
  ];
}
