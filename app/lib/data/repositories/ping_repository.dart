import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/ping.dart';

/// Maps a raw `pings` record. Top-level (like [instantFromRecord]) so the
/// mapping is unit-testable against a hand-built [RecordModel] without a
/// live collection.
Ping pingFromRecord(RecordModel r) => Ping(
  id: r.id,
  coupleId: r.get<String>('couple'),
  fromId: r.get<String>('from'),
  kind: PingKind.byId(r.get<String>('kind')),
  created:
      DateTime.tryParse(r.get<String>('created'))?.toLocal() ?? DateTime.now(),
);

/// `pings` — the one-tap "thinking of you" (kb/features.md). Create +
/// realtime-subscribe only, exactly like [TouchRepository]: the server rules
/// block update entirely and delete for everyone but the purge cron, so
/// neither is exposed here.
///
/// There's deliberately no `list()`. A ping is a moment, not a feed — what
/// the app does with one is show a flourish and raise a notification, both
/// of which only ever concern the ping that just arrived.
class PingRepository {
  PingRepository(this._pb);

  final PocketBase _pb;

  /// Sends a ping. [fromId] must be the caller's own user id — the server
  /// rejects anything else (that's the forgery block). Callers debounce
  /// (see `shouldSendPing`); this method sends whatever it's given.
  Future<void> send({
    required String coupleId,
    required String fromId,
    required PingKind kind,
  }) {
    return _pb
        .collection('pings')
        .create(
          body: {'couple': coupleId, 'from': fromId, 'kind': kind.id},
        );
  }

  /// Fires on every new ping in the couple — including my own, since
  /// PocketBase echoes the creator's own record back. Callers filter on
  /// `fromId` (the notifier's self-echo rule; see [decideNotification]).
  ///
  /// Swallows a subscribe failure (an older server without migration 13) into
  /// a no-op unsubscribe, matching every other realtime repository here.
  Future<UnsubscribeFunc> subscribe(void Function(Ping ping) onPing) async {
    try {
      return await _pb.collection('pings').subscribe('*', (e) {
        if (e.record != null) onPing(pingFromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
