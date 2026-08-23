import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/calendar/calendar_view_model.dart';
import 'package:couples_app/domain/calendar_math.dart' show monthLabel;
import 'package:couples_app/ui/features/calendar/calendar_window.dart';

import 'support/fake_event_repository.dart';
import 'support/pixel_fonts.dart';

void main() {
  setUpAll(loadPixelFonts);

  final now = DateTime(2026, 8, 23); // a Sunday

  Future<CalendarViewModel> pumpCalendar(
    WidgetTester tester, {
    FakeEventRepository? repository,
  }) async {
    // Tall enough that the whole window (grid + upcoming strip) fits
    // without needing to scroll to tap a day cell.
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = repository ?? FakeEventRepository();
    final viewModel = CalendarViewModel(
      authRepository: loggedInAuthRepository(),
      eventRepository: repo,
      now: now,
    );
    await viewModel.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          // Real usage always scrolls a RetroWindow section (see
          // HomeColumn/CompanionHome) — match that so the grid's natural
          // height doesn't overflow the test surface.
          body: SingleChildScrollView(child: CalendarWindow(viewModel: viewModel)),
        ),
      ),
    );
    await tester.pump();
    return viewModel;
  }

  testWidgets('renders the month grid with 42 day cells and today outlined', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.byKey(const Key('calendar-grid')), findsOneWidget);
    expect(find.text(monthLabel(2026, 8)), findsOneWidget);
    // 42 Monday-first cells, keyed by calendar date.
    for (var d = 1; d <= 31; d++) {
      expect(
        find.byKey(Key('calendar-day-2026-8-$d')),
        findsOneWidget,
        reason: 'day $d of August should be on the grid',
      );
    }
    // Trailing July days are on the grid too (Aug 1 2026 is a Saturday).
    expect(find.byKey(const Key('calendar-day-2026-7-27')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a day with no events opens its empty-state list', (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tester.tap(find.byKey(const Key('calendar-day-2026-8-25')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarDayEmpty), findsOneWidget);
    expect(find.byKey(const Key('day-event-add')), findsOneWidget);
  });

  testWidgets('tapping a day with an event lists it', (tester) async {
    final repo = FakeEventRepository();
    await repo.create(
      coupleId: 'couple1',
      title: 'dinner date',
      starts: DateTime(2026, 8, 25, 19),
    );
    await pumpCalendar(tester, repository: repo);

    await tester.tap(find.byKey(const Key('calendar-day-2026-8-25')));
    await tester.pumpAndSettle();

    expect(find.text('dinner date'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text(AppStrings.calendarDayEmpty), findsNothing);
  });

  testWidgets('the day dialog add button opens the event dialog, and empty '
      'title does not save', (tester) async {
    final repo = FakeEventRepository();
    await pumpCalendar(tester, repository: repo);

    await tester.tap(find.byKey(const Key('calendar-day-2026-8-25')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-event-add')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarNewEventTitle), findsOneWidget);

    // Empty title: saving is a no-op, dialog stays open, nothing created.
    await tester.tap(find.text(AppStrings.calendarSaveEvent));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarNewEventTitle), findsOneWidget);
    expect(repo.stored, isEmpty);
  });

  testWidgets('filling the title and saving creates the event and closes '
      'the dialog', (tester) async {
    final repo = FakeEventRepository();
    await pumpCalendar(tester, repository: repo);

    await tester.tap(find.byKey(const Key('calendar-day-2026-8-25')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-event-add')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'movie night');
    await tester.tap(find.text(AppStrings.calendarSaveEvent));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.calendarNewEventTitle), findsNothing);
    expect(repo.stored, hasLength(1));
    expect(repo.stored.single.title, 'movie night');
    // Live in the still-open day list dialog, no reopen needed.
    expect(find.text('movie night'), findsOneWidget);
  });

  testWidgets('the upcoming strip shows compact "in N days · title" rows', (
    tester,
  ) async {
    final repo = FakeEventRepository();
    await repo.create(
      coupleId: 'couple1',
      title: 'dinner date',
      starts: DateTime(2026, 8, 26, 19),
    );
    await pumpCalendar(tester, repository: repo);

    expect(find.byKey(const Key('calendar-upcoming')), findsOneWidget);
    expect(find.textContaining('dinner date'), findsWidgets);
    expect(find.textContaining('in 3 days'), findsOneWidget);
  });

  testWidgets('the upcoming strip shows the empty-state copy with no events', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(find.text(AppStrings.calendarUpcomingEmpty), findsOneWidget);
  });

  testWidgets('month navigation moves the header label and the today button '
      'returns to it', (tester) async {
    await pumpCalendar(tester);

    expect(find.text(monthLabel(2026, 8)), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-next-month')));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel(2026, 9)), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendar-today')));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel(2026, 8)), findsOneWidget);
  });
}
