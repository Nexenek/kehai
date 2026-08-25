import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';
import 'package:couples_app/ui/core/widgets/offline_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('OfflineBadge', () {
    testWidgets('is one warn-coloured pixel square and one quiet word', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const OfflineBadge()));

      expect(find.text(AppStrings.offlineBadge), findsOneWidget);

      final dot = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('offline-badge')),
          matching: find.byType(Container),
        ),
      );
      expect(dot.color, AppColors.light.warn);

      final size = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('offline-badge')),
          matching: find.byType(Container),
        ),
      );
      // Square, and small enough to read as punctuation rather than a
      // button — see [OfflineBadge.dotSize].
      expect(size.width, OfflineBadge.dotSize);
      expect(size.height, OfflineBadge.dotSize);
    });

    test('the label stays lowercase and unpunctuated — a status, not an '
        'alarm', () {
      expect(AppStrings.offlineBadge, 'offline');
    });
  });
}
