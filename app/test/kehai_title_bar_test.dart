import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/app_controller.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/always_on_top_pin.dart';
import 'package:couples_app/ui/core/widgets/kehai_title_bar.dart';

void main() {
  late AppController controller;

  setUp(() => controller = AppController());
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

  testWidgets('wears the app name and real ★ / ♥ window controls', (
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
    await tester.tap(find.text('♥'));
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
    await tester.drag(find.text('♥'), const Offset(40, 20));
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
}
