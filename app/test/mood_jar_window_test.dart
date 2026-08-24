import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/mood_jar_repository.dart';
import 'package:couples_app/domain/models/mood_entry.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/jar/jar_painter.dart';
import 'package:couples_app/ui/features/jar/mood_jar_view_model.dart';
import 'package:couples_app/ui/features/jar/mood_jar_window.dart';

/// Builds a view model wired to a real repository against a fake base URL
/// (never hit — tests set `entries`/`isLoading` directly rather than
/// calling `init()`, same pattern as `board_window_test.dart`'s
/// `_viewModel`).
MoodJarViewModel _viewModel() {
  final pb = PocketBase('https://example.invalid');
  return MoodJarViewModel(
    authRepository: AuthRepository(pb),
    moodJarRepository: MoodJarRepository(pb),
  );
}

MoodEntry _entry(
  String id, {
  String userId = 'me',
  String mood = 'happy',
  String note = '',
  required DateTime created,
}) => MoodEntry(
  id: id,
  coupleId: 'couple1',
  userId: userId,
  mood: mood,
  note: note,
  created: created,
);

/// Wrapped in a [SingleChildScrollView] — every real host of this window
/// (the phone column, the desktop drawer, each spread column) scrolls
/// around it the same way; a bare `Scaffold` here would overflow once a
/// few day groups stack up, which none of the real hosts ever let happen.
Future<void> _pump(WidgetTester tester, MoodJarViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: MoodJarWindow(viewModel: viewModel),
          ),
        ),
      ),
    ),
  );
}

CustomPaint _jarCustomPaint(WidgetTester tester) => tester.widget<CustomPaint>(
  find.descendant(
    of: find.byKey(const Key('jar-glass')),
    matching: find.byType(CustomPaint),
  ),
);

void main() {
  testWidgets('shows the empty state when there are no entries', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = const [];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.jarTitle), findsOneWidget);
    expect(find.text(AppStrings.jarEmpty), findsOneWidget);
    // No beads to draw.
    final painter = _jarCustomPaint(tester).painter as JarPainter;
    expect(painter.beadColors, isEmpty);
  });

  testWidgets('does not show the empty state once entries have loaded', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [_entry('e1', created: DateTime.now())];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.jarEmpty), findsNothing);
  });

  testWidgets('draws one bead per entry', (tester) async {
    final now = DateTime.now();
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [
        _entry('e1', created: now, mood: 'happy'),
        _entry('e2', created: now, mood: 'sleepy'),
        _entry('e3', created: now, mood: 'sad'),
      ];

    await _pump(tester, viewModel);

    final painter = _jarCustomPaint(tester).painter as JarPainter;
    expect(painter.beadColors, hasLength(3));
  });

  testWidgets('an unrecognized mood id falls back to ink rather than '
      'crashing', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [_entry('e1', created: DateTime.now(), mood: 'from_2099')];

    await _pump(tester, viewModel);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final painter = _jarCustomPaint(tester).painter as JarPainter;
    expect(painter.beadColors.single, AppColors.light.ink);
    // The row also shows the raw mood id as its label, rather than hiding
    // the entry.
    expect(find.textContaining('from_2099'), findsOneWidget);
  });

  testWidgets('rows show today/yesterday/an older short date as headings', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final older = today.subtract(const Duration(days: 10));

    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [
        _entry('t', created: today),
        _entry('y', created: yesterday),
        _entry('o', created: older),
      ];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.jarDayToday), findsOneWidget);
    expect(find.text(AppStrings.jarDayYesterday), findsOneWidget);
    // Lowercase "mon d" for anything older — not asserting the exact
    // string here (it's day-of-run dependent), just that neither the
    // today/yesterday strings nor the empty state leaked into its slot.
    expect(find.text(AppStrings.jarEmpty), findsNothing);
  });

  testWidgets('a row shows the mood kaomoji, label, note and "you"/"partner"', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [
        _entry(
          'mine',
          // '' matches AuthRepository.currentUserId when no one is logged
          // in — see files_window_test.dart's identical convention.
          userId: '',
          mood: 'happy',
          note: 'good morning ♡',
          created: DateTime.now(),
        ),
        _entry(
          'theirs',
          userId: 'partner',
          mood: 'sleepy',
          created: DateTime.now(),
        ),
      ];

    await _pump(tester, viewModel);

    expect(find.textContaining('happy'), findsWidgets);
    expect(find.textContaining('you'), findsWidgets);
    expect(find.textContaining('partner'), findsWidgets);
    expect(find.text('good morning ♡'), findsOneWidget);
  });

  testWidgets('newest bead ends up last in the bottom-up pile order', (
    tester,
  ) async {
    // entries is newest-first (repository/view-model contract); the
    // painter wants oldest-first so the newest is both highest in the
    // pile and painted last — the window is responsible for that flip.
    final viewModel = _viewModel()
      ..isLoading = false
      ..entries = [
        _entry('newest', created: DateTime.now(), mood: 'sad'),
        _entry('oldest', created: DateTime.now(), mood: 'happy'),
      ];

    await _pump(tester, viewModel);

    final painter = _jarCustomPaint(tester).painter as JarPainter;
    expect(painter.beadColors.first, AppColors.light.mint); // happy, first
    expect(painter.beadColors.last, AppColors.light.sky); // sad, on top
  });
}
