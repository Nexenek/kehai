import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/countdown.dart';

/// `countdowns` CRUD + realtime — couple-scoped rules already restrict list
/// visibility server-side (see server/migrations/3_shared_content.go), so
/// every method here just talks to the collection directly.
class CountdownRepository {
  CountdownRepository(this._pb);

  final PocketBase _pb;

  Countdown _fromRecord(RecordModel r) => Countdown(
        id: r.id,
        coupleId: r.get<String>('couple'),
        title: r.get<String>('title'),
        date: DateTime.tryParse(r.get<String>('date'))?.toLocal() ?? DateTime.now(),
        kaomoji: r.get<String>('kaomoji'),
      );

  Future<List<Countdown>> fetchAll(String coupleId) async {
    final records = await _pb.collection('countdowns').getFullList(
          filter: 'couple = "$coupleId"',
        );
    return records.map(_fromRecord).toList();
  }

  Future<void> create({
    required String coupleId,
    required String title,
    required DateTime date,
    String kaomoji = '',
  }) {
    return _pb.collection('countdowns').create(body: {
      'couple': coupleId,
      'title': title,
      'date': date.toUtc().toIso8601String(),
      'kaomoji': kaomoji,
    });
  }

  Future<void> update(
    String id, {
    required String title,
    required DateTime date,
    String kaomoji = '',
  }) {
    return _pb.collection('countdowns').update(id, body: {
      'title': title,
      'date': date.toUtc().toIso8601String(),
      'kaomoji': kaomoji,
    });
  }

  Future<void> delete(String id) => _pb.collection('countdowns').delete(id);

  /// Fires on create/update/delete alike — [onChange] gets the raw PB
  /// `action` string ("create"/"update"/"delete") plus the parsed record so
  /// callers can reconcile their local list either way.
  Future<UnsubscribeFunc> subscribe(void Function(String action, Countdown countdown) onChange) {
    return _pb.collection('countdowns').subscribe('*', (e) {
      if (e.record != null) onChange(e.action, _fromRecord(e.record!));
    });
  }
}
