import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/event_repository.dart';
import 'package:couples_app/domain/models/calendar_event.dart';
import 'package:couples_app/domain/models/event_color.dart';

/// In-memory stand-in for `calendar_events` — hands back whatever's in
/// [stored] for a range query, records create/update/delete, and can echo a
/// change back through whatever [CalendarViewModel.init] subscribed, same
/// shape as `_FakeTouchRepository`/`_FakeQuestions` elsewhere in this test
/// suite.
class FakeEventRepository extends EventRepository {
  FakeEventRepository() : super(PocketBase('https://example.invalid'));

  final List<CalendarEvent> stored = [];
  void Function(String action, CalendarEvent event)? _onChange;
  int _idCounter = 0;

  bool get isSubscribed => _onChange != null;

  @override
  Future<List<CalendarEvent>> fetchRange(
    String coupleId,
    DateTime start,
    DateTime end,
  ) async {
    final matches = stored
        .where(
          (e) =>
              e.coupleId == coupleId &&
              !e.starts.isBefore(start) &&
              e.starts.isBefore(end),
        )
        .toList()
      ..sort((a, b) => a.starts.compareTo(b.starts));
    return matches;
  }

  @override
  Future<void> create({
    required String coupleId,
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) async {
    final event = CalendarEvent(
      id: 'e${_idCounter++}',
      coupleId: coupleId,
      title: title,
      starts: starts,
      ends: ends,
      allDay: allDay,
      notes: notes,
      color: color,
    );
    stored.add(event);
    _onChange?.call('create', event);
  }

  @override
  Future<void> update(
    String id, {
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) async {
    final index = stored.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final updated = stored[index].copyWith(
      title: title,
      starts: starts,
      ends: ends,
      clearEnds: ends == null,
      allDay: allDay,
      notes: notes,
      color: color,
    );
    stored[index] = updated;
    _onChange?.call('update', updated);
  }

  @override
  Future<void> delete(String id) async {
    final index = stored.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final removed = stored.removeAt(index);
    _onChange?.call('delete', removed);
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, CalendarEvent event) onChange,
  ) async {
    _onChange = onChange;
    return () async => _onChange = null;
  }
}

/// A logged-in, paired [AuthRepository] — same helper shape as
/// `_loggedInAuthRepository` in thumb_kiss_view_model_test.dart.
AuthRepository loggedInAuthRepository({
  String id = 'me',
  String couple = 'couple1',
}) {
  final pb = PocketBase('https://example.invalid');
  pb.authStore.save(
    'tok',
    RecordModel({
      'id': id,
      'collectionId': 'c',
      'collectionName': 'users',
      'couple': couple,
    }),
  );
  return AuthRepository(pb);
}

/// A logged-out/unpaired [AuthRepository] — `coupleId` reads null, same as
/// a real user who hasn't joined a couple yet.
AuthRepository soloAuthRepository() =>
    AuthRepository(PocketBase('https://example.invalid'));
