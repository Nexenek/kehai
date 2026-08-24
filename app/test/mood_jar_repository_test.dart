import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/mood_jar_repository.dart';

RecordModel _record(Map<String, dynamic> overrides) => RecordModel({
  'id': 'entry1',
  'collectionId': 'mood_entries_col',
  'collectionName': 'mood_entries',
  'couple': 'couple1',
  'user': 'userA',
  'mood': 'happy',
  'note': 'feeling good today',
  'created': '2026-08-23 12:00:00.000Z',
  ...overrides,
});

void main() {
  group('moodEntryFromRecord', () {
    test('maps every field, created coming back local', () {
      final entry = moodEntryFromRecord(_record({}));

      expect(entry.id, 'entry1');
      expect(entry.coupleId, 'couple1');
      expect(entry.userId, 'userA');
      expect(entry.mood, 'happy');
      expect(entry.note, 'feeling good today');
      expect(entry.created.toUtc(), DateTime.utc(2026, 8, 23, 12));
      expect(entry.created.isUtc, isFalse);
    });

    test('note defaults to empty rather than throwing when absent', () {
      final entry = moodEntryFromRecord(_record({'note': null}));
      expect(entry.note, '');
    });

    test('a foreign/unrecognized mood id is carried through as-is — the '
        'repository never validates against MoodCatalog, only the UI '
        'layer falls back', () {
      final entry = moodEntryFromRecord(_record({'mood': 'from_the_future'}));
      expect(entry.mood, 'from_the_future');
    });
  });
}
