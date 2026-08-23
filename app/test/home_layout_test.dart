import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/home_layout.dart';

import 'support/home_sections_stub.dart';

void main() {
  group('resolveHomeLayoutMode', () {
    test('anything non-desktop keeps the original single column', () {
      expect(
        resolveHomeLayoutMode(size: const Size(400, 900), desktop: false),
        HomeLayoutMode.column,
      );
      // Even a wide Android window (tablet, freeform) stays the column —
      // the desktop shapes are opt-in per platform.
      expect(
        resolveHomeLayoutMode(size: const Size(1280, 720), desktop: false),
        HomeLayoutMode.column,
      );
    });

    test('a tall desktop window is the companion pane', () {
      expect(
        resolveHomeLayoutMode(size: const Size(400, 640), desktop: true),
        HomeLayoutMode.companion,
      );
    });

    test('the threshold is the ~1.2 aspect locked in platform-desktop.md', () {
      // Just under and exactly at the threshold stay compact…
      expect(
        resolveHomeLayoutMode(size: const Size(1199, 1000), desktop: true),
        HomeLayoutMode.companion,
      );
      expect(
        resolveHomeLayoutMode(size: const Size(1200, 1000), desktop: true),
        HomeLayoutMode.companion,
      );
      // …and a hair over spreads out.
      expect(
        resolveHomeLayoutMode(size: const Size(1201, 1000), desktop: true),
        HomeLayoutMode.spread,
      );
    });

    test('a maximized 16:9 window spreads', () {
      expect(
        resolveHomeLayoutMode(size: const Size(1920, 1080), desktop: true),
        HomeLayoutMode.spread,
      );
    });

    test('a degenerate size falls back to the companion pane', () {
      expect(
        resolveHomeLayoutMode(size: const Size(400, 0), desktop: true),
        HomeLayoutMode.companion,
      );
    });
  });

  group('HomeBody switches layout with the window', () {
    Future<void> pumpAt(WidgetTester tester, Size size, {bool desktop = true}) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeBody(sections: stubSections(), desktop: desktop),
          ),
        ),
      );
    }

    testWidgets('a 400x640 desktop pane gets the tray, not the spread', (
      tester,
    ) async {
      await pumpAt(tester, const Size(400, 640));

      expect(find.byKey(const Key('home-tray')), findsOneWidget);
      expect(find.byKey(const Key('home-spread')), findsNothing);
      // The partner window is always on screen…
      expect(find.text(stubPartnerText), findsOneWidget);
      // …the sections live behind tray buttons.
      expect(find.byKey(const Key('tray-mood')), findsOneWidget);
      expect(find.byKey(const Key('tray-doodle')), findsOneWidget);
      expect(find.byKey(const Key('tray-countdowns')), findsOneWidget);
      expect(find.byKey(const Key('tray-notes')), findsOneWidget);
      expect(find.text(stubNotesText), findsNothing);
    });

    testWidgets('stretching the window wide swaps in the spread', (
      tester,
    ) async {
      await pumpAt(tester, const Size(1280, 720));

      expect(find.byKey(const Key('home-spread')), findsOneWidget);
      expect(find.byKey(const Key('home-tray')), findsNothing);
      // Everything is on screen at once — no tray, nothing hidden.
      expect(find.text(stubPartnerText), findsOneWidget);
      expect(find.text(stubMoodText), findsOneWidget);
      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.text(stubNotesText), findsOneWidget);
      expect(find.byKey(const Key('tray-mood')), findsNothing);
    });

    testWidgets('crossing the threshold at runtime swaps layouts', (
      tester,
    ) async {
      await pumpAt(tester, const Size(400, 640));
      expect(find.byKey(const Key('home-tray')), findsOneWidget);

      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-spread')), findsOneWidget);
      expect(find.byKey(const Key('home-tray')), findsNothing);

      tester.view.physicalSize = const Size(420, 700);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-tray')), findsOneWidget);
      expect(find.byKey(const Key('home-spread')), findsNothing);
    });

    testWidgets('Android/portrait is untouched: one scrolling column', (
      tester,
    ) async {
      await pumpAt(tester, const Size(400, 800), desktop: false);

      expect(find.byKey(const Key('home-tray')), findsNothing);
      expect(find.byKey(const Key('home-spread')), findsNothing);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text(stubPartnerText), findsOneWidget);
      expect(find.text(stubMoodText), findsOneWidget);
      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.text(stubNotesText), findsOneWidget);
    });
  });
}
