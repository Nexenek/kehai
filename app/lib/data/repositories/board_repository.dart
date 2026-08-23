import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/board_item.dart';
import '../../domain/models/note_color.dart';

/// Maps a raw `board_items` [RecordModel] to a [BoardItem]. Split out as a
/// top-level function (see [InstantRepository]'s `instantFromRecord` doc
/// comment for why) so the mapping is unit-testable without a live
/// collection.
BoardItem boardItemFromRecord(PocketBase pb, RecordModel r) {
  final imageField = r.get<String>('image', '');
  return BoardItem(
    id: r.id,
    coupleId: r.get<String>('couple'),
    type: BoardItemType.fromString(r.get<String>('type')),
    text: r.get<String>('text', ''),
    imageUrl: imageField.isEmpty
        ? null
        : pb.files.getUrl(r, imageField).toString(),
    sticker: r.get<String>('sticker', ''),
    x: r.get<double>('x', 0),
    y: r.get<double>('y', 0),
    rot: r.get<double>('rot', 0),
    z: r.get<double>('z', 0),
    color: NoteColor.fromString(r.get<String?>('color', null)),
  );
}

/// `board_items` — the shared decorable pinboard (kb/features.md "Shared
/// board"). Couple-scoped shared ownership is enforced server-side (see
/// server/migrations/8_board.go's `shared` rule) — either partner can
/// create/move/delete any item, so this repository never distinguishes
/// authorship.
class BoardRepository {
  BoardRepository(this._pb);

  final PocketBase _pb;

  BoardItem _fromRecord(RecordModel r) => boardItemFromRecord(_pb, r);

  Future<List<BoardItem>> fetchAll(String coupleId) async {
    try {
      final records = await _pb
          .collection('board_items')
          .getFullList(filter: 'couple = "$coupleId"');
      return records.map(_fromRecord).toList();
    } on ClientException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<void> createNote({
    required String coupleId,
    required String text,
    required double x,
    required double y,
    required double rot,
    required double z,
    required NoteColor color,
  }) {
    return _pb
        .collection('board_items')
        .create(
          body: {
            'couple': coupleId,
            'type': 'note',
            'text': text,
            'x': x,
            'y': y,
            'rot': rot,
            'z': z,
            'color': color.name,
          },
        );
  }

  Future<void> createSticker({
    required String coupleId,
    required String sticker,
    required double x,
    required double y,
    required double rot,
    required double z,
  }) {
    return _pb
        .collection('board_items')
        .create(
          body: {
            'couple': coupleId,
            'type': 'sticker',
            'sticker': sticker,
            'x': x,
            'y': y,
            'rot': rot,
            'z': z,
          },
        );
  }

  /// Uploads [imageBytes] as a new photo item — multipart (a file field
  /// can't ride a JSON body), same pattern as `InstantRepository.create`.
  Future<void> createPhoto({
    required String coupleId,
    required Uint8List imageBytes,
    required String filename,
    required double x,
    required double y,
    required double rot,
    required double z,
  }) {
    return _pb
        .collection('board_items')
        .create(
          body: {
            'couple': coupleId,
            'type': 'photo',
            'x': x,
            'y': y,
            'rot': rot,
            'z': z,
          },
          files: [
            http.MultipartFile.fromBytes('image', imageBytes, filename: filename),
          ],
        );
  }

  /// Persists a moved/re-stacked item's position + z. Called exactly once,
  /// at drag end — never mid-drag (see `board_drag_logic.dart`'s
  /// `shouldPersistBoardDrag`) — so this is a plain single write; no
  /// debouncing needed in the repository itself.
  Future<void> updatePosition(
    String id, {
    required double x,
    required double y,
    required double z,
  }) {
    return _pb
        .collection('board_items')
        .update(id, body: {'x': x, 'y': y, 'z': z});
  }

  Future<void> delete(String id) => _pb.collection('board_items').delete(id);

  /// Fires on create/update/delete alike. Moves arrive as a plain `update`
  /// — same as any other field edit — so the caller reconciles on the
  /// record's full current state rather than trying to special-case
  /// "this update was a move". Swallows a subscribe failure into a no-op
  /// unsubscribe, matching the other realtime-collection repositories'
  /// "nothing yet" handling.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, BoardItem item) onChange,
  ) async {
    try {
      return await _pb.collection('board_items').subscribe('*', (e) {
        if (e.record != null) onChange(e.action, _fromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
