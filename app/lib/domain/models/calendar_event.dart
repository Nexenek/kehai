import 'package:flutter/foundation.dart';

import 'event_color.dart';

/// A `calendar_events` record — a shared date/time on "our calendar"
/// (server/migrations/11_calendar.go). See that migration's doc comment for
/// why the collection is named `calendar_events` rather than `events`
/// (the name `events` is already taken by the generic activity log from
/// 1_init.go).
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.starts,
    this.ends,
    this.allDay = false,
    this.notes = '',
    this.color = EventColor.pink,
  });

  final String id;
  final String coupleId;
  final String title;

  /// When the event begins. For an all-day event this is date-only in
  /// spirit (time-of-day is normalized to midnight by the dialog before it
  /// ever reaches the repository).
  final DateTime starts;

  /// Optional end — null means "no end set" (a point-in-time event, or an
  /// all-day event with no explicit end date).
  final DateTime? ends;
  final bool allDay;
  final String notes;
  final EventColor color;

  CalendarEvent copyWith({
    String? title,
    DateTime? starts,
    DateTime? ends,
    bool clearEnds = false,
    bool? allDay,
    String? notes,
    EventColor? color,
  }) => CalendarEvent(
    id: id,
    coupleId: coupleId,
    title: title ?? this.title,
    starts: starts ?? this.starts,
    ends: clearEnds ? null : (ends ?? this.ends),
    allDay: allDay ?? this.allDay,
    notes: notes ?? this.notes,
    color: color ?? this.color,
  );
}
