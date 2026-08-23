import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/home_layout.dart';
import 'package:couples_app/ui/features/home/views/home_tray.dart';
import 'package:couples_app/ui/features/home/views/my_mood_window.dart';

import 'support/home_sections_stub.dart';
import 'support/pixel_fonts.dart';

/// The drawer's slide state: [Offset.zero] is fully up, (0, 1) is parked
/// below the tray bar.
Offset drawerOffset(WidgetTester tester) => tester
    .widget<AnimatedSlide>(find.byKey(const Key('home-tray-drawer')))
    .offset;

Duration drawerDuration(WidgetTester tester) => tester
    .widget<AnimatedSlide>(find.byKey(const Key('home-tray-drawer')))
    .duration;

Future<void> pumpTray(
  WidgetTester tester, {
  SectionTaps? taps,
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 640);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: HomeBody(sections: stubSections(taps: taps), desktop: true),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Text metrics matter for the "does it fit" test below.
  setUpAll(loadPixelFonts);

  testWidgets('a tray button slides its drawer up, and closes it again', (
    tester,
  ) async {
    await pumpTray(tester);

    expect(drawerOffset(tester), const Offset(0, 1));

    await tester.tap(find.byKey(const Key('tray-countdowns')));
    await tester.pumpAndSettle();

    expect(drawerOffset(tester), Offset.zero);
    expect(find.text(stubCountdownsText), findsOneWidget);
    // The partner window is never covered up entirely — it stays above the
    // drawer, which is the whole point of the companion pane.
    expect(find.text(stubPartnerText), findsOneWidget);

    // Tapping the active button again puts it away.
    await tester.tap(find.byKey(const Key('tray-countdowns')));
    await tester.pumpAndSettle();
    expect(drawerOffset(tester), const Offset(0, 1));
  });

  testWidgets('only one drawer at a time', (tester) async {
    await pumpTray(tester);

    await tester.tap(find.byKey(const Key('tray-countdowns')));
    await tester.pumpAndSettle();
    expect(find.text(stubCountdownsText), findsOneWidget);

    await tester.tap(find.byKey(const Key('tray-notes')));
    await tester.pumpAndSettle();

    expect(drawerOffset(tester), Offset.zero);
    expect(find.text(stubNotesText), findsOneWidget);
    expect(find.text(stubCountdownsText), findsNothing);
  });

  testWidgets("the section's own close closes the drawer", (tester) async {
    await pumpTray(tester);

    await tester.tap(find.byKey(const Key('tray-mood')));
    await tester.pumpAndSettle();
    expect(drawerOffset(tester), Offset.zero);

    // The stub section calls the onClose the drawer handed it — the real
    // sections wire that to their RetroWindow ♥.
    await tester.tap(find.text(stubMoodText));
    await tester.pumpAndSettle();
    expect(drawerOffset(tester), const Offset(0, 1));
  });

  testWidgets('a closed drawer does not swallow taps', (tester) async {
    await pumpTray(tester);

    // The mood section is mounted (parked below the bar) from the start so
    // it can animate; it must not be interactive while it is down.
    const guard = Key('home-tray-drawer-guard');
    expect(tester.widget<IgnorePointer>(find.byKey(guard)).ignoring, isTrue);

    await tester.tap(find.byKey(const Key('tray-mood')));
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(find.byKey(guard)).ignoring, isFalse);
  });

  testWidgets('the doodle button opens the canvas instead of a drawer', (
    tester,
  ) async {
    final taps = SectionTaps();
    await pumpTray(tester, taps: taps);

    await tester.tap(find.byKey(const Key('tray-doodle')));
    await tester.pumpAndSettle();

    expect(taps.doodle, 1);
    expect(drawerOffset(tester), const Offset(0, 1));
  });

  testWidgets('reduced motion jumps instead of sliding', (tester) async {
    await pumpTray(tester, disableAnimations: true);

    expect(drawerDuration(tester), Duration.zero);

    await tester.tap(find.byKey(const Key('tray-mood')));
    // No settle: with animations disabled the drawer is already there.
    await tester.pump();
    expect(drawerOffset(tester), Offset.zero);
  });

  testWidgets('a real section fits the smallest allowed window', (
    tester,
  ) async {
    // 360×480 is DesktopWindowService.minimumSize — the tightest the user
    // can drag the pane. A real mood window (grid + field + buttons) has to
    // fit in the drawer there without overflowing.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 480);
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HomeBody(
            desktop: true,
            sections: stubSections(
              mood: (context, onClose) => MyMoodWindow(
                selectedMoodId: 'happy',
                onSelectMood: (_) {},
                noteController: controller,
                onNoteChanged: (_) {},
                onSaveNote: (_) {},
                onClose: onClose,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('tray-mood')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.moodPickerTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the slide is the restrained ~200ms easeOutCubic move', (
    tester,
  ) async {
    await pumpTray(tester);

    expect(drawerDuration(tester), kDrawerDuration);
    expect(kDrawerDuration, const Duration(milliseconds: 200));
    expect(
      tester
          .widget<AnimatedSlide>(find.byKey(const Key('home-tray-drawer')))
          .curve,
      Curves.easeOutCubic,
    );
  });
}
