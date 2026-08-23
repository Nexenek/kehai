import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/app_controller.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/always_on_top_pin.dart';
import 'package:couples_app/ui/core/widgets/kehai_title_bar.dart';

void main() {
  late AppController controller;

  setUp(() async {
    // The ✧ sharing button reads `controller.prefs` whenever the log-out
    // row is visible (both are gated on "we're home"), so tests that flip
    // straight to AppStage.home without going through the real init() flow
    // need a seeded prefs instance too.
    SharedPreferences.setMockInitialValues({});
    controller = AppController();
    controller.prefs = await PrefsService.create();
  });
  tearDown(() => controller.dispose());

  Future<void> pumpBar(
    WidgetTester tester, {
    VoidCallback? onMinimize,
    VoidCallback? onClose,
    VoidCallback? onToggleMaximize,
    VoidCallback? onDragStart,
    Widget? pin,
    bool? showLogOut,
  }) {
    return tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: KehaiTitleBar(
              onMinimize: onMinimize,
              onClose: onClose,
              onToggleMaximize: onToggleMaximize,
              onDragStart: onDragStart,
              pin: pin,
              showLogOut: showLogOut,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('wears the app name and real ★ / ♥\uFE0E window controls', (
    tester,
  ) async {
    var minimized = 0;
    var closed = 0;
    await pumpBar(
      tester,
      onMinimize: () => minimized++,
      onClose: () => closed++,
      pin: null,
    );

    expect(find.text(AppStrings.appName), findsOneWidget);

    await tester.tap(find.text('★'));
    await tester.tap(find.text('♥\uFE0E'));
    await tester.pump();

    expect(minimized, 1);
    expect(closed, 1);
  });

  testWidgets('dragging the strip moves the window, double-click maximizes', (
    tester,
  ) async {
    var drags = 0;
    var maximizeToggles = 0;
    await pumpBar(
      tester,
      onDragStart: () => drags++,
      onToggleMaximize: () => maximizeToggles++,
      pin: null,
    );

    await tester.drag(find.text(AppStrings.appName), const Offset(40, 20));
    await tester.pump();
    expect(drags, 1);

    // The window controls are not part of the drag region.
    await tester.drag(find.text('♥\uFE0E'), const Offset(40, 20));
    await tester.pump();
    expect(drags, 1);

    final title = tester.getCenter(find.text(AppStrings.appName));
    await tester.tapAt(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(title);
    await tester.pumpAndSettle();
    expect(maximizeToggles, 1);
  });

  testWidgets('the ✦ pin toggles always-on-top', (tester) async {
    final pinned = ValueNotifier<bool>(false);
    addTearDown(pinned.dispose);
    var toggles = 0;

    await pumpBar(
      tester,
      pin: AlwaysOnTopPin(pinned: pinned, onToggle: () => toggles++),
    );

    await tester.tap(find.text('✦'));
    await tester.pump();
    expect(toggles, 1);

    // The pin reflects the window's real state, not the tap.
    expect(find.byTooltip(AppStrings.alwaysOnTopOffTooltip), findsOneWidget);
    pinned.value = true;
    await tester.pump();
    expect(find.byTooltip(AppStrings.alwaysOnTopOnTooltip), findsOneWidget);
  });

  testWidgets('log out only appears once we are home', (tester) async {
    await pumpBar(tester, pin: null);
    expect(find.text(AppStrings.logOut), findsNothing);

    controller.stage = AppStage.home;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text(AppStrings.logOut), findsOneWidget);
  });

  testWidgets('the ✧ sharing button only appears once home, opens the sharing '
      'window, and reflects the toggle live', (tester) async {
    await pumpBar(tester, pin: null);
    expect(find.text('✧'), findsNothing);

    controller.stage = AppStage.home;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('✧'), findsOneWidget);
    expect(
      find.byTooltip(AppStrings.sharingSettingsTooltipOff),
      findsOneWidget,
    );

    await tester.tap(find.text('✧'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.sharingSettingsTitle), findsOneWidget);
    expect(find.text(AppStrings.shareFocusedAppTitle), findsOneWidget);

    // Both toggle rows read "turn on" while off, so scope the tap to the
    // focused-app row specifically.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('sharing-focused-app-toggle')),
        matching: find.text(AppStrings.shareFocusedAppTurnOn),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.shareFocusedApp, isTrue);

    // The toggle grew the window's content (the "on" label + the second
    // row's body), so scroll "done" into view before tapping it — mirrors
    // how a real short window would need to scroll too.
    await tester.ensureVisible(find.text(AppStrings.sharingSettingsDone));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.sharingSettingsDone));
    await tester.pumpAndSettle();

    // The window actually closed...
    expect(find.text(AppStrings.sharingSettingsTitle), findsNothing);
    // ...and reflects live state without needing to reopen it (the
    // "visible sharing state" the feature promises).
    expect(find.byTooltip(AppStrings.sharingSettingsTooltipOn), findsOneWidget);
  });
}
