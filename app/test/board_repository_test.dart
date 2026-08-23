import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/board_repository.dart';
import 'package:couples_app/domain/models/board_item.dart';
import 'package:couples_app/domain/models/note_color.dart';

void main() {
  group('boardItemFromRecord', () {
    // pb.files.getUrl only does string-building against the record's id +
    // collection id/name — no network call — so a bare client pointed at a
    // fake base URL is enough to exercise the real mapping code (same
    // reasoning as instant_repository_test.dart).
    final pb = PocketBase('https://example.invalid');

    test('maps a note item, including its color', () {
      final record = RecordModel({
        'id': 'item1',
        'collectionId': 'board_items_col',
        'collectionName': 'board_items',
        'couple': 'couple1',
        'type': 'note',
        'text': 'miss you',
        'image': '',
        'sticker': '',
        'x': 0.25,
        'y': 0.75,
        'rot': -6.5,
        'z': 3,
        'color': 'mint',
      });

      final item = boardItemFromRecord(pb, record);

      expect(item.id, 'item1');
      expect(item.coupleId, 'couple1');
      expect(item.type, BoardItemType.note);
      expect(item.text, 'miss you');
      expect(item.imageUrl, isNull);
      expect(item.sticker, '');
      expect(item.x, 0.25);
      expect(item.y, 0.75);
      expect(item.rot, -6.5);
      expect(item.z, 3);
      expect(item.color, NoteColor.mint);
    });

    test('maps a photo item, building the absolute file URL', () {
      final record = RecordModel({
        'id': 'item2',
        'collectionId': 'board_items_col',
        'collectionName': 'board_items',
        'couple': 'couple1',
        'type': 'photo',
        'text': '',
        'image': 'pic.png',
        'sticker': '',
        'x': 0.5,
        'y': 0.5,
        'rot': 0,
        'z': 1,
        'color': '',
      });

      final item = boardItemFromRecord(pb, record);

      expect(item.type, BoardItemType.photo);
      expect(
        item.imageUrl,
        'https://example.invalid/api/files/board_items_col/item2/pic.png',
      );
    });

    test('maps a sticker item and falls back to pink for an empty color', () {
      final record = RecordModel({
        'id': 'item3',
        'collectionId': 'board_items_col',
        'collectionName': 'board_items',
        'couple': 'couple1',
        'type': 'sticker',
        'text': '',
        'image': '',
        'sticker': '♥︎',
        'x': 0.1,
        'y': 0.9,
        'rot': 12,
        'z': 2,
        'color': '',
      });

      final item = boardItemFromRecord(pb, record);

      expect(item.type, BoardItemType.sticker);
      expect(item.sticker, '♥︎');
      expect(item.color, NoteColor.pink);
    });

    test('an unrecognized type falls back to note', () {
      final record = RecordModel({
        'id': 'item4',
        'collectionId': 'board_items_col',
        'collectionName': 'board_items',
        'couple': 'couple1',
        'type': 'something_new',
        'x': 0,
        'y': 0,
      });

      expect(boardItemFromRecord(pb, record).type, BoardItemType.note);
    });
  });
}
