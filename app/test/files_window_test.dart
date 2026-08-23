import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/shared_file_repository.dart';
import 'package:couples_app/domain/models/shared_file.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/files/files_view_model.dart';
import 'package:couples_app/ui/features/files/files_window.dart';

/// Builds a view model wired to real repositories against a fake base URL
/// (never actually hit — the tests set state directly rather than calling
/// `init()`, so no network I/O happens). Same pattern as
/// `instants_window_test.dart`'s `_viewModel`.
FilesViewModel _viewModel() {
  final pb = PocketBase('https://example.invalid');
  return FilesViewModel(
    authRepository: AuthRepository(pb),
    fileRepository: SharedFileRepository(pb),
  );
}

SharedFile _file({
  required String id,
  required String uploadedBy,
  String filename = 'photo.jpg',
  String label = '',
  DateTime? created,
}) {
  return SharedFile(
    id: id,
    coupleId: 'couple1',
    uploadedBy: uploadedBy,
    filename: filename,
    label: label,
    created: created ?? DateTime.now(),
  );
}

Future<void> _pump(WidgetTester tester, FilesViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(width: 400, child: FilesWindow(viewModel: viewModel)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the empty state when there are no files', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..files = const [];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.filesEmpty), findsOneWidget);
    expect(find.text(AppStrings.filesTitle), findsOneWidget);
  });

  testWidgets('does not show the empty state while still loading', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = true
      ..files = const [];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.filesEmpty), findsNothing);
  });

  testWidgets('renders one row per file with a who · Xago caption', (
    tester,
  ) async {
    // uploadedBy '' matches AuthRepository.currentUserId when no one is
    // logged in — stands in for "mine"; anything else is "theirs" (same
    // trick as instants_window_test.dart).
    final mine = _file(
      id: 'mine',
      uploadedBy: '',
      filename: 'archive.zip',
      label: 'vacation photos.zip',
      created: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    final theirs = _file(
      id: 'theirs',
      uploadedBy: 'partner1',
      filename: 'notes.txt',
      created: DateTime.now().subtract(const Duration(hours: 2)),
    );

    final viewModel = _viewModel()
      ..isLoading = false
      ..files = [mine, theirs];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.filesEmpty), findsNothing);
    expect(find.text('vacation photos.zip'), findsOneWidget);
    // theirs has no label, so the row falls back to the raw filename.
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text(AppStrings.filesYouCaption('5m ago')), findsOneWidget);
    expect(find.text(AppStrings.filesThemCaption('2h ago')), findsOneWidget);
  });

  testWidgets('the upload button is always present', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..files = const [];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.filesUpload), findsOneWidget);

    final withFiles = _viewModel()
      ..isLoading = false
      ..files = [_file(id: 'a', uploadedBy: 'x')];
    await _pump(tester, withFiles);

    expect(find.text(AppStrings.filesUpload), findsOneWidget);
  });

  testWidgets('shows a "more" button only when the view model has more', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..files = [_file(id: 'a', uploadedBy: 'x')]
      ..hasMore = true;

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.filesLoadMore), findsOneWidget);
  });
}
