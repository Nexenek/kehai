import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/calendar_event.dart';
import '../../domain/models/event_color.dart';

/// `calendar_events` CRUD + realtime — couple-scoped rules already restrict
/// list visibility server-side (see server/migrations/11_calendar.go), so
/// every method here just talks to the collection directly. Same shape as
/// [CountdownRepository]/`NoteRepository`.
class EventRepository {
  EventRepository(this._pb);

  final PocketBase _pb;

  CalendarEvent _fromRecord(RecordModel r) => CalendarEvent(
    id: r.id,
    coupleId: r.get<String>('couple'),
    title: r.get<String>('title'),
    starts: DateTime.tryParse(r.get<String>('starts'))?.toLocal() ?? DateTime.now(),
    ends: _parseOptional(r.get<String?>('ends', null)),
    allDay: r.get<bool>('all_day'),
    notes: r.get<String>('notes'),
    color: EventColor.fromString(r.get<String?>('color', null)),
  );

  DateTime? _parseOptional(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Month/range list — half-open `[start, end)`, matching
  /// `domain/calendar_math.dart`'s `monthQueryRange`. Sorted by start so
  /// the grid and the upcoming strip can both consume it directly.
  Future<List<CalendarEvent>> fetchRange(
    String coupleId,
    DateTime start,
    DateTime end,
  ) async {
    final records = await _pb
        .collection('calendar_events')
        .getFullList(
          filter:
              'couple = "$coupleId" && starts >= "${start.toUtc().toIso8601String()}" '
              '&& starts < "${end.toUtc().toIso8601String()}"',
          sort: 'starts',
        );
    return records.map(_fromRecord).toList();
  }

  Future<void> create({
    required String coupleId,
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) {
    return _pb
        .collection('calendar_events')
        .create(
          body: {
            'couple': coupleId,
            'title': title,
            'starts': starts.toUtc().toIso8601String(),
            'ends': ends?.toUtc().toIso8601String(),
            'all_day': allDay,
            'notes': notes,
            'color': color.name,
          },
        );
  }

  Future<void> update(
    String id, {
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) {
    return _pb
        .collection('calendar_events')
        .update(
          id,
          body: {
            'title': title,
            'starts': starts.toUtc().toIso8601String(),
            'ends': ends?.toUtc().toIso8601String(),
            'all_day': allDay,
            'notes': notes,
            'color': color.name,
          },
        );
  }

  Future<void> delete(String id) => _pb.collection('calendar_events').delete(id);

  /// Fires on create/update/delete alike — see
  /// `CountdownRepository.subscribe` for why the raw action string is
  /// exposed.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, CalendarEvent event) onChange,
  ) {
    return _pb.collection('calendar_events').subscribe('*', (e) {
      if (e.record != null) onChange(e.action, _fromRecord(e.record!));
    });
  }
}
