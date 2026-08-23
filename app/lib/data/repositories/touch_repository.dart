import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/touch_point.dart';

/// `touches` — ephemeral fingertip positions behind the thumb-kiss feature
/// (kb/features.md "Thumb-kiss"). Create + realtime-subscribe only: the
/// server rules block update entirely and delete to everyone but the purge
/// cron, so this repository never exposes either.
class TouchRepository {
  TouchRepository(this._pb);

  final PocketBase _pb;

  TouchPoint _fromRecord(RecordModel r) => TouchPoint(
    userId: r.get<String>('user'),
    x: r.get<double>('x', 0),
    y: r.get<double>('y', 0),
    at:
        DateTime.tryParse(r.get<String>('created'))?.toLocal() ??
        DateTime.now(),
  );

  /// Posts my current fingertip position. Callers throttle how often this
  /// is called (see `thumb_kiss_logic.dart`'s `shouldSendTouch`) — this
  /// method itself just sends whatever it's given.
  Future<void> send({
    required String coupleId,
    required String userId,
    required double x,
    required double y,
  }) {
    return _pb
        .collection('touches')
        .create(body: {'couple': coupleId, 'user': userId, 'x': x, 'y': y});
  }

  /// Fires on every new touch point in the couple (create is the only
  /// action that ever happens — see the class doc comment). Swallows a
  /// subscribe failure into a no-op unsubscribe, matching the other
  /// realtime-collection repositories' "nothing yet" handling.
  Future<UnsubscribeFunc> subscribe(
    void Function(TouchPoint touch) onChange,
  ) async {
    try {
      return await _pb.collection('touches').subscribe('*', (e) {
        if (e.record != null) onChange(_fromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
