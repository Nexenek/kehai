import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/mood.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/mood_picker.dart';

void main() {
  testWidgets('tapping a mood tile reports its id back', (tester) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MoodPicker(
            selectedId: MoodCatalog.all.first.id,
            onSelect: (id) => selected = id,
          ),
        ),
      ),
    );

    final sleepyMood = MoodCatalog.all.firstWhere((m) => m.id == 'sleepy');
    await tester.tap(find.text(sleepyMood.label));
    await tester.pump();

    expect(selected, 'sleepy');
  });
}
