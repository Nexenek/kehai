import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/partner_status.dart';

/// One `statuses` record per user, upserted whenever the user picks a mood
/// (and/or note). Realtime subscription drives the partner card's live
/// updates.
class StatusRepository {
  StatusRepository(this._pb);

  final PocketBase _pb;

  PartnerStatus _fromRecord(RecordModel r) => PartnerStatus(
        userId: r.get<String>('user'),
        moodId: r.get<String>('mood'),
        note: r.get<String>('note'),
        sourceKind: SourceKind.fromString(r.get<String>('source_kind')),
        updated: DateTime.tryParse(r.get<String>('updated'))?.toLocal() ?? DateTime.now(),
      );

  Future<PartnerStatus?> fetchStatus(String userId) async {
    try {
      final record = await _pb.collection('statuses').getFirstListItem('user = "$userId"');
      return _fromRecord(record);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Upserts the caller's own status row.
  Future<void> upsertMyStatus({
    required String userId,
    required String moodId,
    required String note,
    required SourceKind sourceKind,
  }) async {
    final body = {
      'user': userId,
      'mood': moodId,
      'note': note,
      'source_kind': sourceKind.name,
    };

    try {
      final existing = await _pb.collection('statuses').getFirstListItem('user = "$userId"');
      await _pb.collection('statuses').update(existing.id, body: body);
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _pb.collection('statuses').create(body: body);
    }
  }

  /// Subscribes to all changes in `statuses` (rules already scope this to
  /// the caller's couple). Fires with the freshly-parsed [PartnerStatus].
  Future<UnsubscribeFunc> subscribe(void Function(PartnerStatus status) onChange) {
    return _pb.collection('statuses').subscribe('*', (e) {
      if (e.record != null) onChange(_fromRecord(e.record!));
    });
  }
}
