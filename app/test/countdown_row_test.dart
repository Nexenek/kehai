import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/countdown.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/countdown_row.dart';

void main() {
  testWidgets('CountdownRow renders "today!!" for a countdown dated today', (tester) async {
    final now = DateTime(2026, 8, 23, 14, 30);
    final countdown = Countdown(
      id: '1',
      coupleId: 'c1',
      title: "date night",
      date: DateTime(2026, 8, 23), // same calendar date as `now`, different time
      kaomoji: '(｡♥‿♥｡)',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CountdownRow(countdown: countdown, now: now),
        ),
      ),
    );

    expect(find.text(AppStrings.countdownToday), findsOneWidget);
    expect(find.text('date night'), findsOneWidget);
    expect(find.text('(｡♥‿♥｡)'), findsOneWidget);
  });

  testWidgets('CountdownRow renders "in N days" for a future countdown', (tester) async {
    final now = DateTime(2026, 8, 23);
    final countdown = Countdown(id: '2', coupleId: 'c1', title: 'trip', date: DateTime(2026, 10, 4));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: CountdownRow(countdown: countdown, now: now)),
      ),
    );

    expect(find.text('in 42 days'), findsOneWidget);
  });

  testWidgets('CountdownRow renders "N days ago" for a past countdown', (tester) async {
    final now = DateTime(2026, 8, 23);
    final countdown = Countdown(id: '3', coupleId: 'c1', title: 'anniversary dinner', date: DateTime(2026, 8, 13));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: CountdownRow(countdown: countdown, now: now)),
      ),
    );

    expect(find.text('10 days ago'), findsOneWidget);
  });
}
