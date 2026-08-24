import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/home_layout.dart';

import 'support/home_sections_stub.dart';

/// A fresh [PrefsService] over a fresh (optionally pre-seeded) mock
/// SharedPreferences store — same pattern as prefs_service_test.dart.
Future<PrefsService> fakePrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return PrefsService.create();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    Future<void> pumpAt(
      WidgetTester tester,
      Size size, {
      bool desktop = true,
      PrefsService? prefs,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final resolvedPrefs = prefs ?? await fakePrefs();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeBody(
              sections: stubSections(),
              desktop: desktop,
              prefs: resolvedPrefs,
            ),
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
      // …the five primaries live on the bar…
      expect(find.byKey(const Key('tray-mood')), findsOneWidget);
      expect(find.byKey(const Key('tray-doodle')), findsOneWidget);
      expect(find.byKey(const Key('tray-pet')), findsOneWidget);
      expect(find.byKey(const Key('tray-thumbkiss')), findsOneWidget);
      expect(find.byKey(const Key('tray-more')), findsOneWidget);
      // …and the rest live behind ✚, not on the bar itself.
      expect(find.byKey(const Key('tray-countdowns')), findsNothing);
      expect(find.byKey(const Key('tray-notes')), findsNothing);
      expect(find.byKey(const Key('tray-map')), findsNothing);
      expect(find.text(stubNotesText), findsNothing);
      expect(find.text(stubMapText), findsNothing);
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
      expect(find.text(stubPetText), findsOneWidget);
      expect(find.text(stubThumbKissText), findsOneWidget);
      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.text(stubCalendarText), findsOneWidget);
      expect(find.text(stubNotesText), findsOneWidget);
      expect(find.text(stubBoardText), findsOneWidget);
      expect(find.text(stubQuestionText), findsOneWidget);
      expect(find.text(stubInstantsText), findsOneWidget);
      // The map is the spread's rightmost content column, alongside files
      // and the jar.
      expect(find.text(stubMapText), findsOneWidget);
      expect(find.text(stubFilesText), findsOneWidget);
      expect(find.text(stubJarText), findsOneWidget);
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

    testWidgets(
      'Android/portrait is untouched in shape: one scrolling column',
      (tester) async {
        await pumpAt(tester, const Size(400, 800), desktop: false);

        expect(find.byKey(const Key('home-tray')), findsNothing);
        expect(find.byKey(const Key('home-spread')), findsNothing);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        // The partner card is always on screen, uncollapsible.
        expect(find.text(stubPartnerText), findsOneWidget);
        // Mood is the one section expanded by default.
        expect(find.text(stubMoodText), findsOneWidget);
      },
    );
  });

  group('HomeColumn section collapsing', () {
    Future<void> pumpColumn(
      WidgetTester tester, {
      required PrefsService prefs,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeBody(
              sections: stubSections(),
              desktop: false,
              prefs: prefs,
            ),
          ),
        ),
      );
    }

    testWidgets('partner card is always present, never a collapsed strip', (
      tester,
    ) async {
      await pumpColumn(tester, prefs: await fakePrefs());

      expect(find.text(stubPartnerText), findsOneWidget);
    });

    testWidgets('everything but mood starts collapsed, as a labeled strip', (
      tester,
    ) async {
      await pumpColumn(tester, prefs: await fakePrefs());

      // Mood is expanded by default…
      expect(find.text(stubMoodText), findsOneWidget);
      expect(find.byKey(const Key('home-collapsed-mood')), findsNothing);

      // …everything else starts as a collapsed strip, glyph + label
      // showing, its content nowhere in the tree.
      for (final entry in {
        'pet': stubPetText,
        'question': stubQuestionText,
        'thumbkiss': stubThumbKissText,
        'countdowns': stubCountdownsText,
        'calendar': stubCalendarText,
        'notes': stubNotesText,
        'instants': stubInstantsText,
        'files': stubFilesText,
        'board': stubBoardText,
        'art': stubArtText,
        'map': stubMapText,
        'jar': stubJarText,
      }.entries) {
        expect(
          find.byKey(Key('home-collapsed-${entry.key}')),
          findsOneWidget,
          reason: '${entry.key} should start collapsed',
        );
        expect(find.text(entry.value), findsNothing);
      }
    });

    testWidgets('tapping a collapsed strip expands that section', (
      tester,
    ) async {
      await pumpColumn(tester, prefs: await fakePrefs());

      expect(find.text(stubCountdownsText), findsNothing);
      await tester.tap(find.byKey(const Key('home-collapsed-countdowns')));
      await tester.pumpAndSettle();

      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.byKey(const Key('home-collapsed-countdowns')), findsNothing);
    });

    testWidgets("tapping the expanded section's close collapses it again", (
      tester,
    ) async {
      await pumpColumn(tester, prefs: await fakePrefs());
      await tester.tap(find.byKey(const Key('home-collapsed-countdowns')));
      await tester.pumpAndSettle();
      expect(find.text(stubCountdownsText), findsOneWidget);

      // The stub's own content is the "close" — same contract as the real
      // sections wiring their RetroWindow ♥ to onClose.
      await tester.tap(find.text(stubCountdownsText));
      await tester.pumpAndSettle();

      expect(find.text(stubCountdownsText), findsNothing);
      expect(
        find.byKey(const Key('home-collapsed-countdowns')),
        findsOneWidget,
      );
    });

    testWidgets('collapsed/expanded state persists across a fresh prefs load', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final firstPrefs = await PrefsService.create();
      await pumpColumn(tester, prefs: firstPrefs);

      // Expand countdowns, collapse mood.
      await tester.tap(find.byKey(const Key('home-collapsed-countdowns')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(stubMoodText));
      await tester.pumpAndSettle();

      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.byKey(const Key('home-collapsed-mood')), findsOneWidget);

      // A fresh PrefsService, backed by the same (mocked) disk, should
      // reproduce exactly that layout on the next launch.
      final reloadedPrefs = await PrefsService.create();
      await pumpColumn(tester, prefs: reloadedPrefs);

      expect(find.text(stubCountdownsText), findsOneWidget);
      expect(find.byKey(const Key('home-collapsed-countdowns')), findsNothing);
      expect(find.byKey(const Key('home-collapsed-mood')), findsOneWidget);
      expect(find.text(stubMoodText), findsNothing);
    });

    testWidgets('an unrecognised saved section name is tolerated, not fatal', (
      tester,
    ) async {
      final prefs = await fakePrefs({
        'collapsed_home_sections': ['mood', 'some_future_section'],
      });

      await pumpColumn(tester, prefs: prefs);

      // Mood collapsed as saved, and the app doesn't crash on the name it
      // doesn't recognise.
      expect(find.byKey(const Key('home-collapsed-mood')), findsOneWidget);
      expect(find.text(stubMoodText), findsNothing);
    });

    testWidgets(
      'the portal strip always shows (it never collapses) and reaches the '
      'curtain directly, not a drawer',
      (tester) async {
        final taps = SectionTaps();
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: HomeBody(
                sections: stubSections(taps: taps),
                desktop: false,
                prefs: await fakePrefs(),
              ),
            ),
          ),
        );

        final strip = find.byKey(const Key('home-portal-entry'));
        expect(strip, findsOneWidget);
        await tester.ensureVisible(strip);
        await tester.pumpAndSettle();

        await tester.tap(strip);
        await tester.pumpAndSettle();

        expect(taps.portal, 1);
        // Still there, still itself — nothing expanded in its place.
        expect(find.byKey(const Key('home-portal-entry')), findsOneWidget);
      },
    );
  });
}
