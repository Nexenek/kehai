import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/note.dart';
import '../../domain/models/note_color.dart';

/// `notes` CRUD + realtime — couple-scoped rules already restrict list
/// visibility server-side (see server/migrations/3_shared_content.go).
class NoteRepository {
  NoteRepository(this._pb);

  final PocketBase _pb;

  Note _fromRecord(RecordModel r) => Note(
        id: r.id,
        coupleId: r.get<String>('couple'),
        title: r.get<String>('title'),
        body: r.get<String>('body'),
        color: NoteColor.fromString(r.get<String?>('color', null)),
        pinned: r.get<bool>('pinned'),
      );

  Future<List<Note>> fetchAll(String coupleId) async {
    final records = await _pb.collection('notes').getFullList(
          filter: 'couple = "$coupleId"',
        );
    return records.map(_fromRecord).toList();
  }

  Future<void> create({
    required String coupleId,
    required String title,
    required String body,
    required NoteColor color,
    bool pinned = false,
  }) {
    return _pb.collection('notes').create(body: {
      'couple': coupleId,
      'title': title,
      'body': body,
      'color': color.name,
      'pinned': pinned,
    });
  }

  Future<void> update(
    String id, {
    required String title,
    required String body,
    required NoteColor color,
    bool pinned = false,
  }) {
    return _pb.collection('notes').update(id, body: {
      'title': title,
      'body': body,
      'color': color.name,
      'pinned': pinned,
    });
  }

  Future<void> delete(String id) => _pb.collection('notes').delete(id);

  /// Fires on create/update/delete alike — see [CountdownRepository.subscribe]
  /// for why the raw action string is exposed.
  Future<UnsubscribeFunc> subscribe(void Function(String action, Note note) onChange) {
    return _pb.collection('notes').subscribe('*', (e) {
      if (e.record != null) onChange(e.action, _fromRecord(e.record!));
    });
  }
}
