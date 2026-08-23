import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/retro_window.dart';

void main() {
  testWidgets('RetroWindow renders its title and child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: RetroWindow(
            title: 'our desktop',
            child: Text('hello, love'),
          ),
        ),
      ),
    );

    expect(find.text('our desktop'), findsOneWidget);
    expect(find.text('hello, love'), findsOneWidget);
    // Decorative win-chrome glyphs.
    expect(find.text('★'), findsOneWidget);
    expect(find.text('♥'), findsOneWidget);
  });
}
