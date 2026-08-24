import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/portal_signal.dart';

/// Maps a raw `portal_signals` record. Top-level (like `pingFromRecord`)
/// so the mapping is unit-testable against a hand-built [RecordModel]
/// without a live collection. Answers null for a `kind` this build doesn't
/// know — see [PortalSignalKind.byId].
PortalSignal? portalSignalFromRecord(RecordModel r) {
  final kind = PortalSignalKind.byId(r.get<String>('kind'));
  if (kind == null) return null;
  return PortalSignal(
    id: r.id,
    fromId: r.get<String>('from'),
    kind: kind,
    // JSONField comes back as whatever was stored; the human signals store
    // nothing at all, which arrives as null rather than an empty map.
    payload: r.get<Map<String, dynamic>?>('payload', null) ?? const {},
    created:
        DateTime.tryParse(r.get<String>('created'))?.toLocal() ??
        DateTime.now(),
  );
}

/// `portal_signals` — the handshake channel behind portal mode (see
/// server/migrations/16_portal.go). Create + realtime-subscribe only,
/// exactly like `PingRepository` and `TouchRepository`: the server blocks
/// update entirely and delete for everyone but the purge cron, so neither
/// is exposed here.
///
/// There's deliberately no `list()`. A signal is a moment in a handshake
/// that completes in seconds; replaying old ones would mean answering a
/// knock from twenty minutes ago (the engine guards against exactly that
/// even for live ones — see its staleness window).
///
/// No media ever touches this collection. It carries a knock, a yes/no, two
/// SDPs and a handful of ICE candidate lines; the video goes peer-to-peer.
class PortalSignalRepository {
  PortalSignalRepository(this._pb);

  final PocketBase _pb;

  /// My own user id, straight from the auth store rather than passed in —
  /// this is the id the server will stamp on anything we create anyway (the
  /// `from = @request.auth.id` forgery block), so taking it from the caller
  /// could only ever introduce a way to get it wrong.
  String get _myId => _pb.authStore.record?.id ?? '';

  String? get _coupleId {
    final couple = _pb.authStore.record?.get<String>('couple');
    return (couple == null || couple.isEmpty) ? null : couple;
  }

  /// Sends one signal as me. `async` rather than a plain future-returning
  /// method so the no-couple case comes back as a *failed future* instead
  /// of a synchronous throw — the engine treats a failed send as "the
  /// portal isn't available right now", and a synchronous throw would
  /// escape past the `catch` on paths that only await the result later.
  Future<void> create(
    PortalSignalKind kind, {
    Map<String, dynamic> payload = const {},
  }) async {
    final coupleId = _coupleId;
    if (coupleId == null) {
      throw StateError('portal signal with no couple');
    }
    await _pb
        .collection('portal_signals')
        .create(
          body: {
            'couple': coupleId,
            // The forgery-safe half: the server rule only accepts this
            // value, so sending anything else is a 400, never a spoof.
            'from': _myId,
            'kind': kind.id,
            'payload': payload,
          },
        );
  }

  /// Fires on every new signal from the *partner*. PocketBase echoes the
  /// creator's own record back on the same subscription (see
  /// `PingRepository.subscribe`'s note), so the self-echo is dropped right
  /// here rather than in the caller: unlike a ping — where my own echo is
  /// meaningful to the notifier's "did I send this?" rule — a portal signal
  /// never means anything to the peer that sent it. Half a state machine
  /// answering its own offer is a bug with no upside.
  ///
  /// [onOwnSignal], if given, is where that dropped self-echo goes instead
  /// of nowhere — the same account logged in on a *second* device (a phone
  /// that knocked, a desktop sitting in `knocked`) also produces `from == me`
  /// signals, and one device needs to hear the other one's answer to avoid
  /// double-accepting the same knock (see `PortalEngine`'s multi-device
  /// guard). Every other caller — including every other collection's
  /// `subscribe` in this app — has no use for its own echo and leaves this
  /// null, which reproduces the old drop-silently behaviour exactly.
  ///
  /// Swallows a subscribe failure (an older server without migration 16)
  /// into a no-op unsubscribe, matching every other realtime repository
  /// here.
  Future<UnsubscribeFunc> subscribe(
    void Function(PortalSignal signal) onSignal, {
    void Function(PortalSignal signal)? onOwnSignal,
  }) async {
    final me = _myId;
    try {
      return await _pb.collection('portal_signals').subscribe('*', (e) {
        final record = e.record;
        if (record == null) return;
        final signal = portalSignalFromRecord(record);
        if (signal == null) return;
        if (signal.fromId == me) {
          onOwnSignal?.call(signal);
          return;
        }
        onSignal(signal);
      });
    } catch (_) {
      return () async {};
    }
  }
}
