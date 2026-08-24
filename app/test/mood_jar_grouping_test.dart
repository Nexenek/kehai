import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/mood_entry.dart';
import 'package:couples_app/domain/mood_jar_grouping.dart';

MoodEntry _entry(String id, DateTime created, {String userId = 'me'}) =>
    MoodEntry(
      id: id,
      coupleId: 'couple1',
      userId: userId,
      mood: 'happy',
      note: '',
      created: created,
    );

void main() {
  final now = DateTime(2026, 8, 24, 15, 30);

  group('groupMoodEntriesByDay', () {
    test('empty input groups to nothing', () {
      expect(groupMoodEntriesByDay(const [], now: now), isEmpty);
    });

    test('buckets today, yesterday and older into separate, correctly '
        'kinded groups', () {
      final entries = [
        _entry('today', DateTime(2026, 8, 24, 9)),
        _entry('yesterday', DateTime(2026, 8, 23, 22)),
        _entry('older', DateTime(2026, 8, 20, 8)),
      ];

      final groups = groupMoodEntriesByDay(entries, now: now);

      expect(groups, hasLength(3));
      expect(groups[0].kind, JarDayKind.today);
      expect(groups[0].entries.single.id, 'today');
      expect(groups[1].kind, JarDayKind.yesterday);
      expect(groups[1].entries.single.id, 'yesterday');
      expect(groups[2].kind, JarDayKind.older);
      expect(groups[2].entries.single.id, 'older');
    });

    test('groups are ordered newest-day-first', () {
      final entries = [
        _entry('a', DateTime(2026, 8, 10)),
        _entry('b', DateTime(2026, 8, 24)),
        _entry('c', DateTime(2026, 8, 15)),
      ];

      final groups = groupMoodEntriesByDay(entries, now: now);

      expect(groups.map((g) => g.day), [
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 15),
        DateTime(2026, 8, 10),
      ]);
    });

    test('entries landing the same calendar day share one group, in the '
        "input's order", () {
      final entries = [
        _entry('second', DateTime(2026, 8, 24, 14)),
        _entry('first', DateTime(2026, 8, 24, 8)),
      ];

      final groups = groupMoodEntriesByDay(entries, now: now);

      expect(groups, hasLength(1));
      expect(groups.single.entries.map((e) => e.id), ['second', 'first']);
    });

    test('a day exactly 2 days back is "older", not "yesterday"', () {
      final entries = [_entry('e', DateTime(2026, 8, 22, 23, 59))];
      final groups = groupMoodEntriesByDay(entries, now: now);
      expect(groups.single.kind, JarDayKind.older);
    });

    test('the boundary at midnight flips today into yesterday', () {
      final lateLastNight = _entry('e', DateTime(2026, 8, 23, 23, 59));

      // Just before midnight on the 24th: the 23rd is "yesterday".
      final beforeMidnight = groupMoodEntriesByDay([
        lateLastNight,
      ], now: DateTime(2026, 8, 24, 0, 1));
      expect(beforeMidnight.single.kind, JarDayKind.yesterday);

      // A minute later than that "now", nothing about the entry changed —
      // still the 23rd, still yesterday relative to the 24th.
      final stillSameDay = groupMoodEntriesByDay([
        lateLastNight,
      ], now: DateTime(2026, 8, 24, 23, 59));
      expect(stillSameDay.single.kind, JarDayKind.yesterday);

      // But once "now" rolls into the 25th, that same entry is "older".
      final nextDay = groupMoodEntriesByDay([
        lateLastNight,
      ], now: DateTime(2026, 8, 25, 0, 1));
      expect(nextDay.single.kind, JarDayKind.older);
    });
  });
}
