import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/ghost_state.dart';
import '../../domain/models/location_point.dart';
import 'auth_repository.dart';

/// Reads the `locations` collection and owns my own ghost switch
/// (kb/contracts.md "Location").
///
/// Read-only on purpose: points are written exclusively by the server's
/// OwnTracks ingest route (`POST /api/owntracks`), and the collection has
/// no client create/update/delete rule at all. The app visualizes; the
/// tracker reports.
///
/// Everything here tolerates the collection not existing yet: the server
/// half of phase 3 lands separately, and "no location yet ( . .)" is a
/// perfectly good thing for the window to say in the meantime.
class LocationRepository {
  LocationRepository(this._pb, this._authRepository);

  final PocketBase _pb;
  final AuthRepository _authRepository;

  /// Codes that mean "there's nothing here (yet)" rather than "something
  /// broke": 404 for a missing collection *or* an empty single-item query,
  /// 403 for rules that haven't been relaxed for this couple yet.
  static bool _isAbsent(ClientException e) =>
      e.statusCode == 404 || e.statusCode == 403;

  /// PocketBase record → domain. Public so it can be exercised directly
  /// with hand-built records in tests, and so the domain layer doesn't have
  /// to import the client.
  static LocationPoint pointFromRecord(RecordModel r) => LocationPoint(
    id: r.id,
    userId: r.get<String>('user'),
    lat: r.get<double>('lat', 0),
    lon: r.get<double>('lon', 0),
    recorded:
        DateTime.tryParse(r.get<String>('recorded'))?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    accuracy: _positive(r.get<double?>('accuracy', null)),
    battery: _positive(r.get<double?>('battery', null)),
    velocity: r.get<double?>('velocity', null),
  );

  /// A PocketBase NumberField stores 0 both for "zero" and for "never
  /// reported" — same reasoning as [DeviceRepository]'s battery handling.
  /// Neither a 0 m accuracy radius nor a 0% battery-at-fix-time is a real
  /// reading, so both read back as unknown.
  static double? _positive(double? value) =>
      (value == null || value <= 0) ? null : value;

  /// `users.ghost_until` off any users record — mine or the partner's.
  static DateTime? ghostUntilFromRecord(RecordModel r) =>
      parseGhostUntil(r.get<String>('ghost_until', ''));

  /// The latest point for [userId] — contract query: `sort=-recorded,
  /// limit 1, filter user=X`. Null when they have no points (or the
  /// collection isn't there yet).
  Future<LocationPoint?> latestForUser(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final page = await _pb
          .collection('locations')
          .getList(
            page: 1,
            perPage: 1,
            filter: 'user = "$userId"',
            sort: '-recorded',
          );
      return page.items.isEmpty ? null : pointFromRecord(page.items.first);
    } on ClientException catch (e) {
      if (_isAbsent(e)) return null;
      rethrow;
    }
  }

  /// Realtime on `locations`. Fires for either of us — the caller filters
  /// by [LocationPoint.userId], the same shape as
  /// [DeviceRepository.subscribe].
  ///
  /// A failed subscribe (collection missing) yields a no-op unsubscribe
  /// rather than throwing: the window still works, it just won't update
  /// itself until the server side exists.
  Future<UnsubscribeFunc> subscribe(
    void Function(LocationPoint point) onChange,
  ) async {
    try {
      return await _pb.collection('locations').subscribe('*', (e) {
        if (e.record != null) onChange(pointFromRecord(e.record!));
      });
    } on ClientException catch (e) {
      if (_isAbsent(e)) return () async {};
      rethrow;
    }
  }

  /// Current `ghost_until` for [userId]. Used for my own switch; the
  /// partner's comes along with [CoupleRepository.fetchPartner] instead of
  /// costing a second request.
  Future<DateTime?> readGhostUntil(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final record = await _pb.collection('users').getOne(userId);
      return ghostUntilFromRecord(record);
    } on ClientException catch (e) {
      if (_isAbsent(e)) return null;
      rethrow;
    }
  }

  /// Sets (or clears) my own pause — a PATCH of my `users` record, which
  /// the stock PocketBase update rule already allows. Returns the
  /// `ghost_until` now in effect so the caller can render the exact time it
  /// lifts without a round trip.
  ///
  /// `null` means "sharing on": the field is cleared with `''`, PocketBase's
  /// clear value for a date field.
  Future<DateTime?> setGhost(GhostOption? option, {DateTime? now}) async {
    final userId = _authRepository.currentUserId;
    if (userId.isEmpty) return null;
    final until = ghostUntilFor(option, now: now);
    await _pb
        .collection('users')
        .update(
          userId,
          body: {'ghost_until': until?.toUtc().toIso8601String() ?? ''},
        );
    return until;
  }

  /// Live `ghost_until` changes on the `users` collection, so a pause
  /// started on one of my devices shows up on the others — and so the
  /// partner's pause appears the moment they tap it, not on next refresh.
  Future<UnsubscribeFunc> subscribeGhost(
    void Function(String userId, DateTime? ghostUntil) onChange,
  ) async {
    try {
      return await _pb.collection('users').subscribe('*', (e) {
        final record = e.record;
        if (record != null) onChange(record.id, ghostUntilFromRecord(record));
      });
    } on ClientException catch (e) {
      if (_isAbsent(e)) return () async {};
      rethrow;
    }
  }
}
