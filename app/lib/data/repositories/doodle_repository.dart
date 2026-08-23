import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/doodle.dart';

/// `doodles` — a little PNG one partner sends the other. Couple-scoped
/// visibility + "author must be me" + "either partner can delete" are
/// enforced server-side; this repository just talks to the collection.
/// Immutable (no `update` — see [Doodle]'s doc comment).
class DoodleRepository {
  DoodleRepository(this._pb);

  final PocketBase _pb;

  Doodle _fromRecord(RecordModel r) => Doodle(
    id: r.id,
    coupleId: r.get<String>('couple'),
    authorId: r.get<String>('author'),
    imageUrl: _pb.files.getUrl(r, r.get<String>('image')).toString(),
    created:
        DateTime.tryParse(r.get<String>('created'))?.toLocal() ??
        DateTime.now(),
  );

  /// The most recent doodle [authorId] sent within [coupleId], or null if
  /// they haven't sent one (yet, or it's since been deleted).
  Future<Doodle?> latestByAuthor(String coupleId, String authorId) async {
    final page = await _pb
        .collection('doodles')
        .getList(
          page: 1,
          perPage: 1,
          filter: 'couple = "$coupleId" && author = "$authorId"',
          sort: '-created',
        );
    return page.items.isEmpty ? null : _fromRecord(page.items.first);
  }

  /// Uploads [pngBytes] as a new doodle. [authorId] must be the caller's
  /// own user id — the server rejects anything else.
  Future<void> create({
    required String coupleId,
    required String authorId,
    required Uint8List pngBytes,
  }) {
    return _pb
        .collection('doodles')
        .create(
          body: {'couple': coupleId, 'author': authorId},
          files: [
            http.MultipartFile.fromBytes(
              'image',
              pngBytes,
              filename: 'doodle.png',
            ),
          ],
        );
  }

  Future<void> delete(String id) => _pb.collection('doodles').delete(id);

  /// Fires on create/delete alike (doodles are immutable, so no 'update'
  /// action ever arrives) — see [CountdownRepository.subscribe] for why the
  /// raw action string is exposed.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, Doodle doodle) onChange,
  ) {
    return _pb.collection('doodles').subscribe('*', (e) {
      if (e.record != null) onChange(e.action, _fromRecord(e.record!));
    });
  }
}
