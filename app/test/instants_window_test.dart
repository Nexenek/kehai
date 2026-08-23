import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/instant_repository.dart';
import 'package:couples_app/domain/models/instant.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/instants/instants_view_model.dart';
import 'package:couples_app/ui/features/instants/instants_window.dart';

/// Builds a view model wired to real repositories against a fake base URL
/// (never actually hit — the tests set state directly rather than calling
/// `init()`, so no network I/O happens).
InstantsViewModel _viewModel() {
  final pb = PocketBase('https://example.invalid');
  return InstantsViewModel(
    authRepository: AuthRepository(pb),
    instantRepository: InstantRepository(pb),
  );
}

Instant _instant({
  required String id,
  required String authorId,
  String caption = '',
  DateTime? created,
}) {
  return Instant(
    id: id,
    coupleId: 'couple1',
    authorId: authorId,
    imageUrl: 'https://example.invalid/api/files/instants/$id/photo.jpg',
    caption: caption,
    created: created ?? DateTime.now(),
  );
}

void main() {
  testWidgets('shows the empty state when there are no instants', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..instants = const [];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InstantsWindow(viewModel: viewModel)),
      ),
    );

    expect(find.text(AppStrings.instantsEmpty), findsOneWidget);
    expect(find.text(AppStrings.instantsTitle), findsOneWidget);
    expect(find.byType(AspectRatio), findsNothing);
  });

  testWidgets('does not show the empty state while still loading', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = true
      ..instants = const [];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: InstantsWindow(viewModel: viewModel)),
      ),
    );

    expect(find.text(AppStrings.instantsEmpty), findsNothing);
  });

  testWidgets('renders one tile per instant, newest-first order untouched', (
    tester,
  ) async {
    // authorId '' matches AuthRepository.currentUserId when no one is
    // logged in — stands in for "mine"; anything else is "theirs".
    final mine = _instant(
      id: 'mine',
      authorId: '',
      created: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    final theirs = _instant(
      id: 'theirs',
      authorId: 'partner1',
      caption: 'thinking of you',
      created: DateTime.now().subtract(const Duration(hours: 2)),
    );

    final viewModel = _viewModel()
      ..isLoading = false
      ..instants = [mine, theirs];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: InstantsWindow(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.instantsEmpty), findsNothing);
    // One tile per instant (each is an AspectRatio square in the grid).
    expect(find.byType(AspectRatio), findsNWidgets(2));
    expect(find.text('5m ago'), findsOneWidget);
    expect(find.text('2h ago'), findsOneWidget);
  });

  testWidgets('shows a "load more" button only when the view model has more', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..instants = [_instant(id: 'a', authorId: 'x')]
      ..hasMore = true;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: InstantsWindow(viewModel: viewModel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.instantsLoadMore), findsOneWidget);
  });
}
