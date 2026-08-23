import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/calendar_event.dart';
import 'package:couples_app/domain/models/event_color.dart';
import 'package:couples_app/ui/features/calendar/calendar_view_model.dart';

import 'support/fake_event_repository.dart';

void main() {
  final now = DateTime(2026, 8, 23);

  group('init', () {
    test('loads the visible month plus the upcoming window, and subscribes', () async {
      final repo = FakeEventRepository();
      repo.stored.addAll([
        // In August (visible month).
        _e(repo, id: 'in-month', couple: 'couple1', title: 'dinner', starts: DateTime(2026, 8, 25)),
        // Outside August but inside the 60-day upcoming window.
        _e(repo, id: 'upcoming', couple: 'couple1', title: 'trip', starts: DateTime(2026, 9, 10)),
        // Someone else's couple.
        _e(repo, id: 'other-couple', couple: 'couple2', title: 'nope', starts: DateTime(2026, 8, 25)),
      ]);
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );

      await viewModel.init();

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.eventsForDay(DateTime(2026, 8, 25)).map((e) => e.id), ['in-month']);
      expect(viewModel.upcoming.map((e) => e.id), ['in-month', 'upcoming']);
      expect(repo.isSubscribed, isTrue);
    });

    test('an unpaired user (no couple) still finishes loading', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: soloAuthRepository(),
        eventRepository: repo,
        now: now,
      );

      await viewModel.init();

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.upcoming, isEmpty);
    });
  });

  group('month navigation', () {
    test('nextMonth/prevMonth page the visible month and fetch it', () async {
      final repo = FakeEventRepository();
      repo.stored.add(
        _e(repo, id: 'sep', couple: 'couple1', title: 'sept event', starts: DateTime(2026, 9, 5)),
      );
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();
      expect(viewModel.visibleMonth, DateTime(2026, 8));

      await viewModel.nextMonth();
      expect(viewModel.visibleMonth, DateTime(2026, 9));
      expect(viewModel.eventsForDay(DateTime(2026, 9, 5)).map((e) => e.id), ['sep']);

      await viewModel.prevMonth();
      expect(viewModel.visibleMonth, DateTime(2026, 8));
    });

    test('goToToday returns to the current month', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();
      await viewModel.nextMonth();
      await viewModel.nextMonth();
      expect(viewModel.visibleMonth, DateTime(2026, 10));

      await viewModel.goToToday();
      expect(viewModel.visibleMonth, DateTime(2026, 8));
    });

    test('paging clears the day selection', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();
      viewModel.selectDay(DateTime(2026, 8, 10));
      expect(viewModel.selectedDay, isNotNull);

      await viewModel.nextMonth();
      expect(viewModel.selectedDay, isNull);
    });
  });

  group('isToday / isInVisibleMonth', () {
    test('flags today and dims out-of-month grid cells', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();

      expect(viewModel.isToday(DateTime(2026, 8, 23)), isTrue);
      expect(viewModel.isToday(DateTime(2026, 8, 24)), isFalse);
      expect(viewModel.isInVisibleMonth(DateTime(2026, 8, 1)), isTrue);
      expect(viewModel.isInVisibleMonth(DateTime(2026, 7, 31)), isFalse);
    });
  });

  group('add/update/delete', () {
    test('addEvent creates through the repository and lands via realtime', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();

      await viewModel.addEvent(
        title: 'movie night',
        starts: DateTime(2026, 8, 26, 20),
        color: EventColor.sky,
      );

      final events = viewModel.eventsForDay(DateTime(2026, 8, 26));
      expect(events, hasLength(1));
      expect(events.single.title, 'movie night');
      expect(events.single.color, EventColor.sky);
    });

    test('updateEvent + deleteEvent propagate through realtime too', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();
      await viewModel.addEvent(title: 'draft', starts: DateTime(2026, 8, 26));
      final id = viewModel.eventsForDay(DateTime(2026, 8, 26)).single.id;

      await viewModel.updateEvent(id, title: 'renamed', starts: DateTime(2026, 8, 27));
      expect(viewModel.eventsForDay(DateTime(2026, 8, 26)), isEmpty);
      expect(viewModel.eventsForDay(DateTime(2026, 8, 27)).single.title, 'renamed');

      await viewModel.deleteEvent(id);
      expect(viewModel.eventsForDay(DateTime(2026, 8, 27)), isEmpty);
    });

    test('a realtime change for another couple is ignored', () async {
      final repo = FakeEventRepository();
      final viewModel = CalendarViewModel(
        authRepository: loggedInAuthRepository(couple: 'couple1'),
        eventRepository: repo,
        now: now,
      );
      await viewModel.init();

      await repo.create(
        coupleId: 'couple2',
        title: 'not ours',
        starts: DateTime(2026, 8, 26),
      );

      expect(viewModel.eventsForDay(DateTime(2026, 8, 26)), isEmpty);
    });
  });
}

CalendarEvent _e(
  FakeEventRepository repo, {
  required String id,
  required String couple,
  required String title,
  required DateTime starts,
}) {
  return CalendarEvent(id: id, coupleId: couple, title: title, starts: starts);
}
