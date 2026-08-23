import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ghost_state.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/location/views/location_window.dart';

import 'support/pixel_fonts.dart';

/// Everything here runs with no [LocationPoint]s, so the window shows its
/// empty state instead of a live [CoupleMap] — no tile fetches in tests.
/// The distance line is passed in already formatted (see
/// location_math_test.dart for the rule that produces it), so all of this
/// window's own copy is still exercised.
void main() {
  setUpAll(loadPixelFonts);

  final now = DateTime(2026, 8, 23, 14, 30);

  Future<void> pumpWindow(
    WidgetTester tester, {
    String? distanceLine,
    GhostState myGhost = GhostState.off,
    GhostState partnerGhost = GhostState.off,
    String partnerName = 'mati',
    String? errorText,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationWindow(
              partnerName: partnerName,
              myPoint: null,
              partnerPoint: null,
              myGhost: myGhost,
              partnerGhost: partnerGhost,
              distanceLine: distanceLine,
              errorText: errorText,
              now: now,
              onChooseGhost: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('with nothing reported yet it says so, kindly', (tester) async {
    await pumpWindow(tester);

    expect(find.byKey(const Key('location-empty')), findsOneWidget);
    expect(find.text(AppStrings.locationEmpty), findsOneWidget);
    expect(find.text(AppStrings.locationTitle), findsOneWidget);
    // No distance and no partner-pause line to show.
    expect(find.byKey(const Key('location-distance')), findsNothing);
    expect(find.byKey(const Key('partner-ghost-line')), findsNothing);
    // The sharing switch is always available, even with no points at all.
    expect(find.byKey(const Key('ghost-controls')), findsOneWidget);
  });

  testWidgets('the distance line shows when there is one', (tester) async {
    await pumpWindow(tester, distanceLine: '~4.2 km apart ♡\uFE0E');

    expect(find.text('~4.2 km apart ♡\uFE0E'), findsOneWidget);
  });

  testWidgets("a partner's timed pause is stated plainly, with its end", (
    tester,
  ) async {
    await pumpWindow(
      tester,
      partnerGhost: GhostState.until(DateTime(2026, 8, 23, 18, 0)),
    );

    expect(
      find.text(AppStrings.partnerGhostUntil('mati', '18:00')),
      findsOneWidget,
    );
  });

  testWidgets("a partner's open-ended pause never shows a year-2100 date", (
    tester,
  ) async {
    await pumpWindow(
      tester,
      partnerGhost: GhostState.indefinite(indefiniteGhostUntil),
    );

    final line = tester
        .widget<Text>(find.byKey(const Key('partner-ghost-line')))
        .data!;
    expect(line, AppStrings.partnerGhostIndefinite('mati'));
    expect(line, isNot(contains('2100')));
  });

  testWidgets('an unnamed partner still gets a name in the pause line', (
    tester,
  ) async {
    await pumpWindow(
      tester,
      partnerName: '',
      partnerGhost: GhostState.indefinite(indefiniteGhostUntil),
    );

    expect(
      find.text(
        AppStrings.partnerGhostIndefinite(AppStrings.partnerCardTitleFallback),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed ghost change says so honestly', (tester) async {
    await pumpWindow(tester, errorText: AppStrings.ghostFailed);

    expect(find.text(AppStrings.ghostFailed), findsOneWidget);
  });
}
