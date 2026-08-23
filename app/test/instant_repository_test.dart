import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/instant_repository.dart';

void main() {
  group('instantFromRecord', () {
    // `pb.files.getUrl` only does string-building against the record's id
    // + collection id/name — no network call — so a bare client pointed at
    // a fake base URL is enough to exercise the real mapping code.
    final pb = PocketBase('https://example.invalid');

    test('maps every field, including the absolute file URL', () {
      final record = RecordModel({
        'id': 'inst1',
        'collectionId': 'instants_col',
        'collectionName': 'instants',
        'couple': 'couple1',
        'author': 'user1',
        'image': 'photo.jpg',
        'caption': 'lunch! 🍜',
        'created': '2026-08-23 12:34:56.000Z',
      });

      final instant = instantFromRecord(pb, record);

      expect(instant.id, 'inst1');
      expect(instant.coupleId, 'couple1');
      expect(instant.authorId, 'user1');
      expect(instant.caption, 'lunch! 🍜');
      expect(
        instant.imageUrl,
        'https://example.invalid/api/files/instants_col/inst1/photo.jpg',
      );
      expect(instant.created.toUtc(), DateTime.utc(2026, 8, 23, 12, 34, 56));
    });

    test('an empty caption round-trips as an empty string', () {
      final record = RecordModel({
        'id': 'inst2',
        'collectionId': 'instants_col',
        'collectionName': 'instants',
        'couple': 'couple1',
        'author': 'user1',
        'image': 'photo.png',
        'caption': '',
        'created': '2026-08-23 12:34:56.000Z',
      });

      expect(instantFromRecord(pb, record).caption, '');
    });

    test('an unparsable created falls back to "now" rather than throwing', () {
      final record = RecordModel({
        'id': 'inst3',
        'collectionId': 'instants_col',
        'collectionName': 'instants',
        'couple': 'couple1',
        'author': 'user1',
        'image': 'photo.png',
        'caption': '',
        'created': 'not-a-date',
      });

      final before = DateTime.now();
      final instant = instantFromRecord(pb, record);
      final after = DateTime.now();

      expect(
        instant.created.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        instant.created.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });
}
