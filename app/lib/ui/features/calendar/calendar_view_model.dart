import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/calendar_math.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/event_color.dart';

/// Drives the calendar RetroWindow: the visible month's grid, the upcoming
/// strip, and add/edit/delete. Realtime-subscribed the same way
/// [CountdownsViewModel] is.
///
/// Every event this view model has ever fetched (any month paged to, plus
/// the rolling "upcoming" window loaded on [init]) is kept in one map keyed
/// by id, so paging back to a month already visited doesn't refetch it and
/// the upcoming strip can see events outside the currently-visible month.
class CalendarViewModel extends ChangeNotifier {
  CalendarViewModel({
    required AuthRepository authRepository,
    required EventRepository eventRepository,
    DateTime? now,
  }) : _authRepository = authRepository,
       _eventRepository = eventRepository,
       _now = now ?? DateTime.now() {
    visibleMonth = DateTime(_now.year, _now.month);
  }

  final AuthRepository _authRepository;
  final EventRepository _eventRepository;
  final DateTime _now;

  /// How far past today the "upcoming" pool is pre-loaded — generous enough
  /// that the strip almost never comes up empty just because nothing in the
  /// currently-visible month qualifies.
  static const _upcomingWindow = Duration(days: 60);

  bool isLoading = true;
  late DateTime visibleMonth;
  DateTime? selectedDay;

  final Map<String, CalendarEvent> _events = {};

  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;

  /// The "now" this view model was built with — injectable for tests, same
  /// reasoning as `CountdownRow.now`. Widgets should read upcoming-strip day
  /// labels off this rather than calling `DateTime.now()` themselves, or a
  /// test-injected `now` silently stops applying past the view model.
  DateTime get now => _now;

  /// The 42 Monday-first cells for [visibleMonth] (see
  /// `domain/calendar_math.dart`).
  List<DateTime> get gridDays =>
      monthGridDays(visibleMonth.year, visibleMonth.month);

  bool isInVisibleMonth(DateTime day) =>
      isInMonth(day, visibleMonth.year, visibleMonth.month);

  bool isToday(DateTime day) => dateOnly(day) == dateOnly(_now);

  bool isSelected(DateTime day) =>
      selectedDay != null && dateOnly(day) == selectedDay;

  String get visibleMonthLabel => monthLabel(visibleMonth.year, visibleMonth.month);

  Map<DateTime, List<CalendarEvent>> get _grid => bucketEventsByDay(
    _events.values.toList(),
    rangeStart: gridDays.first,
    rangeEnd: gridDays.last.add(const Duration(days: 1)),
  );

  List<CalendarEvent> eventsForDay(DateTime day) =>
      _grid[dateOnly(day)] ?? const [];

  /// The next 3 upcoming events across the whole loaded pool (not just the
  /// visible month) — see the class doc comment.
  List<CalendarEvent> get upcoming =>
      upcomingEvents(_events.values.toList(), now: _now, limit: 3);

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        await _mergeRange(coupleId, visibleMonth.year, visibleMonth.month);
        final upcomingEvents = await _eventRepository.fetchRange(
          coupleId,
          dateOnly(_now),
          dateOnly(_now).add(_upcomingWindow),
        );
        for (final e in upcomingEvents) {
          _events[e.id] = e;
        }
      } catch (_) {
        // Leave whatever loaded — the window still renders its empty state.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _eventRepository.subscribe((action, event) {
      if (event.coupleId != _coupleId) return;
      if (action == 'delete') {
        _events.remove(event.id);
      } else {
        _events[event.id] = event;
      }
      notifyListeners();
    });
  }

  Future<void> _mergeRange(String coupleId, int year, int month) async {
    final range = monthQueryRange(year, month);
    final events = await _eventRepository.fetchRange(
      coupleId,
      range.start,
      range.end,
    );
    for (final e in events) {
      _events[e.id] = e;
    }
  }

  Future<void> _goToMonth(DateTime month) async {
    visibleMonth = DateTime(month.year, month.month);
    selectedDay = null;
    notifyListeners();
    final coupleId = _coupleId;
    if (coupleId == null) return;
    try {
      await _mergeRange(coupleId, visibleMonth.year, visibleMonth.month);
      notifyListeners();
    } catch (_) {
      // Whatever was already loaded for this month (if anything) stays.
    }
  }

  Future<void> nextMonth() =>
      _goToMonth(DateTime(visibleMonth.year, visibleMonth.month + 1));

  Future<void> prevMonth() =>
      _goToMonth(DateTime(visibleMonth.year, visibleMonth.month - 1));

  Future<void> goToToday() => _goToMonth(DateTime(_now.year, _now.month));

  void selectDay(DateTime day) {
    selectedDay = dateOnly(day);
    notifyListeners();
  }

  void clearSelection() {
    if (selectedDay == null) return;
    selectedDay = null;
    notifyListeners();
  }

  Future<void> addEvent({
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _eventRepository.create(
      coupleId: coupleId,
      title: title,
      starts: starts,
      ends: ends,
      allDay: allDay,
      notes: notes,
      color: color,
    );
  }

  Future<void> updateEvent(
    String id, {
    required String title,
    required DateTime starts,
    DateTime? ends,
    bool allDay = false,
    String notes = '',
    EventColor color = EventColor.pink,
  }) {
    return _eventRepository.update(
      id,
      title: title,
      starts: starts,
      ends: ends,
      allDay: allDay,
      notes: notes,
      color: color,
    );
  }

  Future<void> deleteEvent(String id) => _eventRepository.delete(id);

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
