import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ghost_state.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/pixel_button.dart';
import 'package:couples_app/ui/features/location/views/ghost_controls.dart';

import 'support/pixel_fonts.dart';

void main() {
  setUpAll(loadPixelFonts);

  final now = DateTime(2026, 8, 23, 14, 30);
  final chosen = <Object?>[];

  setUp(chosen.clear);

  Future<void> pumpControls(
    WidgetTester tester,
    GhostState state, {
    bool busy = false,
    Size size = const Size(400, 640),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: GhostControls(
              state: state,
              busy: busy,
              now: now,
              onChoose: chosen.add,
            ),
          ),
        ),
      ),
    );
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<PixelButton>(find.byKey(Key(key))).onPressed != null;

  String label(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('ghost-state-label')))
      .data!;

  testWidgets('sharing: says so, and "sharing on" has nothing to do', (
    tester,
  ) async {
    await pumpControls(tester, GhostState.off);

    expect(label(tester), AppStrings.ghostRowSharing);
    expect(enabled(tester, 'ghost-resume'), isFalse);
    // The three pauses are all offered.
    expect(enabled(tester, 'ghost-1h'), isTrue);
    expect(enabled(tester, 'ghost-tomorrow'), isTrue);
    expect(enabled(tester, 'ghost-indefinite'), isTrue);
  });

  testWidgets('a timed pause spells out when it lifts', (tester) async {
    await pumpControls(
      tester,
      GhostState.until(DateTime(2026, 8, 23, 15, 30)),
    );

    expect(label(tester), AppStrings.ghostRowPausedUntil('15:30'));
    expect(enabled(tester, 'ghost-resume'), isTrue);
  });

  testWidgets('a pause running into tomorrow says "tomorrow"', (tester) async {
    await pumpControls(tester, GhostState.until(DateTime(2026, 8, 24, 8)));

    expect(label(tester), AppStrings.ghostRowPausedUntil('tomorrow 8:00'));
  });

  testWidgets('an indefinite pause never shows the year-2100 sentinel', (
    tester,
  ) async {
    await pumpControls(tester, GhostState.indefinite(indefiniteGhostUntil));

    expect(label(tester), AppStrings.ghostRowPausedIndefinite);
    expect(label(tester), isNot(contains('2100')));
    expect(enabled(tester, 'ghost-resume'), isTrue);
  });

  testWidgets('every button reports the option it stands for', (tester) async {
    await pumpControls(tester, GhostState.off);

    await tester.tap(find.byKey(const Key('ghost-1h')));
    await tester.tap(find.byKey(const Key('ghost-tomorrow')));
    await tester.tap(find.byKey(const Key('ghost-indefinite')));
    await tester.pump();

    expect(chosen, [
      GhostOption.hour,
      GhostOption.untilTomorrow,
      GhostOption.indefinite,
    ]);
  });

  testWidgets('"sharing on" turns it back on with a null option', (
    tester,
  ) async {
    await pumpControls(
      tester,
      GhostState.until(now.add(const Duration(hours: 1))),
    );

    await tester.tap(find.byKey(const Key('ghost-resume')));
    await tester.pump();

    expect(chosen, [null]);
  });

  testWidgets('a change in flight disables everything, so it cannot race', (
    tester,
  ) async {
    await pumpControls(
      tester,
      GhostState.until(now.add(const Duration(hours: 1))),
      busy: true,
    );

    for (final key in const [
      'ghost-1h',
      'ghost-tomorrow',
      'ghost-indefinite',
      'ghost-resume',
    ]) {
      expect(enabled(tester, key), isFalse, reason: '$key while busy');
    }

    await tester.tap(find.byKey(const Key('ghost-1h')));
    await tester.pump();
    expect(chosen, isEmpty);
  });

  testWidgets('the honest-pause explainer is always on screen', (tester) async {
    await pumpControls(tester, GhostState.off);
    expect(find.text(AppStrings.ghostExplainer), findsOneWidget);
  });

  testWidgets('the row wraps instead of overflowing a narrow drawer', (
    tester,
  ) async {
    // 360 wide is DesktopWindowService.minimumSize — the tightest the
    // companion pane goes.
    await pumpControls(
      tester,
      GhostState.off,
      size: const Size(360, 480),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ghost-1h')), findsOneWidget);
    expect(find.byKey(const Key('ghost-resume')), findsOneWidget);
  });
}
