import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/update_service.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/offline_badge.dart';
import 'package:couples_app/ui/core/widgets/update_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('what the chip says', () {
    test('the daily check is invisible', () {
      // Nothing about a background check belongs on a home screen.
      expect(UpdateChip.labelFor(UpdateStage.idle), isNull);
      expect(UpdateChip.labelFor(UpdateStage.checking), isNull);
    });

    test('an offer names the version', () {
      expect(
        UpdateChip.labelFor(UpdateStage.available, version: '1.0.3'),
        'v1.0.3 is here — tap to update',
      );
    });

    test('the same line becomes the progress readout', () {
      expect(
        UpdateChip.labelFor(UpdateStage.downloading, progress: 0.427),
        'updating… 42%',
      );
      expect(UpdateChip.labelFor(UpdateStage.downloading), 'updating… 0%');
    });

    test('a failure offers a retry, not an explanation', () {
      expect(UpdateChip.labelFor(UpdateStage.failed), AppStrings.updateFailed);
    });

    test('only the two ends of the sequence are tappable', () {
      expect(UpdateChip.isTappable(UpdateStage.available), isTrue);
      expect(UpdateChip.isTappable(UpdateStage.failed), isTrue);
      expect(UpdateChip.isTappable(UpdateStage.downloading), isFalse);
      expect(UpdateChip.isTappable(UpdateStage.applying), isFalse);
    });

    test('the copy stays lowercase and unpunctuated, like the offline '
        'badge', () {
      expect(AppStrings.updateFailed, AppStrings.updateFailed.toLowerCase());
      expect(AppStrings.updateAvailable('1.0.3'), startsWith('v1.0.3'));
    });
  });

  group('rendering', () {
    testWidgets('renders nothing at all while idle', (tester) async {
      await tester.pumpWidget(_wrap(const UpdateChip(stage: UpdateStage.idle)));

      expect(find.byKey(const Key('update-chip')), findsNothing);
    });

    testWidgets('is one accent pixel square and one quiet line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const UpdateChip(stage: UpdateStage.available, version: '1.0.3')),
      );

      expect(find.text(AppStrings.updateAvailable('1.0.3')), findsOneWidget);

      final dot = find.descendant(
        of: find.byKey(const Key('update-chip')),
        matching: find.byType(Container),
      );
      expect(tester.widget<Container>(dot).color, AppColors.light.accent);
      // Same square, same size as the badge it shares a slot with.
      expect(tester.getSize(dot).width, OfflineBadge.dotSize);
      expect(tester.getSize(dot).height, OfflineBadge.dotSize);
    });

    testWidgets('a failure borrows the offline badge\'s warn colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const UpdateChip(stage: UpdateStage.failed)),
      );

      final dot = find.descendant(
        of: find.byKey(const Key('update-chip')),
        matching: find.byType(Container),
      );
      expect(tester.widget<Container>(dot).color, AppColors.light.warn);
    });

    testWidgets('tapping an offer starts the update', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          UpdateChip(
            stage: UpdateStage.available,
            version: '1.0.3',
            onTap: () async => taps++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('update-chip-tap')));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('mid-download there is nothing to tap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          UpdateChip(
            stage: UpdateStage.downloading,
            progress: 0.5,
            onTap: () async {},
          ),
        ),
      );

      expect(find.text('updating… 50%'), findsOneWidget);
      expect(find.byKey(const Key('update-chip-tap')), findsNothing);
    });
  });
}
