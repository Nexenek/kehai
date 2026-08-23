import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/board_repository.dart';
import 'package:couples_app/domain/models/board_item.dart';
import 'package:couples_app/domain/models/note_color.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/board/board_view_model.dart';
import 'package:couples_app/ui/features/board/board_window.dart';

/// Builds a view model wired to real repositories against a fake base URL
/// (never actually hit — tests set `items`/`isLoading` directly rather than
/// calling `init()`, so no network I/O happens). Same pattern as
/// `instants_window_test.dart`'s `_viewModel`.
BoardViewModel _viewModel() {
  final pb = PocketBase('https://example.invalid');
  return BoardViewModel(
    authRepository: AuthRepository(pb),
    boardRepository: BoardRepository(pb),
  );
}

BoardItem _note(String id, {double x = 0.5, double y = 0.5, double z = 1}) =>
    BoardItem(
      id: id,
      coupleId: 'couple1',
      type: BoardItemType.note,
      text: 'miss you',
      x: x,
      y: y,
      z: z,
      color: NoteColor.mint,
    );

BoardItem _photo(String id, {double x = 0.3, double y = 0.3, double z = 2}) =>
    BoardItem(
      id: id,
      coupleId: 'couple1',
      type: BoardItemType.photo,
      imageUrl: 'https://example.invalid/api/files/board_items/$id/pic.png',
      x: x,
      y: y,
      z: z,
    );

// A flower, not a heart/star — the RetroWindow chrome itself already draws
// a decorative ♥/★ (close/minimize), so a colliding glyph here would make
// `find.text` ambiguous between "our sticker" and "the window's own chrome".
BoardItem _sticker(
  String id, {
  double x = 0.7,
  double y = 0.7,
  double z = 3,
}) => BoardItem(
  id: id,
  coupleId: 'couple1',
  type: BoardItemType.sticker,
  sticker: '✿',
  x: x,
  y: y,
  z: z,
);

Future<void> _pump(WidgetTester tester, BoardViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(width: 400, child: BoardWindow(viewModel: viewModel)),
      ),
    ),
  );
}

void main() {
  testWidgets(
    "shows the empty state ('let's fill it together') when there are no items",
    (tester) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..items = const [];

      await _pump(tester, viewModel);

      expect(find.text(AppStrings.boardTitle), findsOneWidget);
      expect(find.text(AppStrings.boardEmpty), findsOneWidget);
    },
  );

  testWidgets('does not show the empty state while still loading', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = true
      ..items = const [];

    await _pump(tester, viewModel);

    expect(find.text(AppStrings.boardEmpty), findsNothing);
  });

  testWidgets('renders one tile per item, across all three types', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..items = [_note('n1'), _photo('p1'), _sticker('s1')];

    await _pump(tester, viewModel);
    await tester.pump();

    expect(find.text(AppStrings.boardEmpty), findsNothing);
    // Note text and sticker glyph render as plain text on the board.
    expect(find.text('miss you'), findsOneWidget);
    expect(find.text('✿'), findsOneWidget);
    // The photo tile renders a network Image.
    expect(find.byType(Image), findsOneWidget);
  });
}
