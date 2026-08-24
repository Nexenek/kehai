import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/pet_repository.dart';
import 'package:couples_app/domain/models/pet.dart';
import 'package:couples_app/domain/models/pet_event.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/pet/pet_painter.dart';
import 'package:couples_app/ui/features/pet/pet_sprite_view.dart';
import 'package:couples_app/ui/features/pet/pet_state.dart';
import 'package:couples_app/ui/features/pet/pet_view_model.dart';
import 'package:couples_app/ui/features/pet/pet_window.dart';

/// Mid-afternoon: awake. Care actions are never tapped in these tests, so
/// the repositories are real objects pointed at a URL that is never hit.
final _afternoon = DateTime(2026, 8, 23, 15);
final _night = DateTime(2026, 8, 24, 2);

PetViewModel _viewModel({DateTime? now}) {
  final pb = PocketBase('https://example.invalid');
  return PetViewModel(
    authRepository: AuthRepository(pb),
    petRepository: PetRepository(pb),
    clock: () => now ?? _afternoon,
  );
}

Pet _pet({
  String name = 'mochi',
  PetVariant variant = PetVariant.blob,
  PetOutfit outfit = PetOutfit.none,
  Duration fedAgo = Duration.zero,
  Duration petAgo = Duration.zero,
  DateTime? now,
}) {
  final clock = now ?? _afternoon;
  return Pet(
    id: 'pet1',
    coupleId: 'couple1',
    name: name,
    variant: variant,
    outfit: outfit,
    fedAt: clock.subtract(fedAgo),
    petAt: clock.subtract(petAgo),
  );
}

Future<void> _pumpWindow(
  WidgetTester tester,
  PetViewModel viewModel, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: SizedBox(width: 360, child: PetWindow(viewModel: viewModel)),
        ),
      ),
    ),
  );
}

List<Color?> _paintedCells(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(PetSpriteView),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as PetPainter).cells;
}

void main() {
  testWidgets('shows the name and the derived state line', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet();

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petTitle), findsOneWidget);
    expect(find.text('mochi'), findsOneWidget);
    expect(find.text(AppStrings.petLineFullCozy), findsOneWidget);
  });

  testWidgets('an unnamed pet shows as kehai-chan', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet(name: '');

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petDefaultName), findsOneWidget);
  });

  testWidgets('a long-unfed pet is wistful, never scolding', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet(
        fedAgo: const Duration(days: 3),
        petAgo: const Duration(days: 3),
      );

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petLineHungryCuddles), findsOneWidget);
    // The care buttons are still just invitations — nothing is disabled or
    // marked urgent.
    expect(find.text(AppStrings.petFeed), findsOneWidget);
  });

  testWidgets('between 23:00 and 07:00 the pet naps', (tester) async {
    final viewModel = _viewModel(now: _night)
      ..isLoading = false
      ..pet = _pet(now: _night);

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petLineSleepy), findsOneWidget);
  });

  testWidgets('offers all four care actions', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet();

    await _pumpWindow(tester, viewModel);

    for (final label in [
      AppStrings.petFeed,
      AppStrings.petPet,
      AppStrings.petDress,
      AppStrings.petRename,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('while adopting it says so, without an empty frame', (
    tester,
  ) async {
    final viewModel = _viewModel()..isLoading = true;

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petAdopting), findsOneWidget);
    expect(find.byType(PetSpriteView), findsNothing);
  });

  testWidgets('an unreachable pet gets a gentle line, not an error', (
    tester,
  ) async {
    final viewModel = _viewModel()..isLoading = false;

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petUnavailable), findsOneWidget);
  });

  testWidgets('a failed care action surfaces its message', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet()
      ..error = AppStrings.petActionFailed;

    await _pumpWindow(tester, viewModel);

    expect(find.text(AppStrings.petActionFailed), findsOneWidget);
  });

  testWidgets('the pet breathes: frame two sits one cell lower', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet();

    await _pumpWindow(tester, viewModel);
    final firstFrame = _paintedCells(tester);
    expect(
      firstFrame,
      buildPetCells(
        variant: PetVariant.blob,
        outfit: PetOutfit.none,
        expression: PetExpression.happy,
        blushing: true,
        colors: AppColors.light,
      ),
    );

    await tester.pump(const Duration(milliseconds: 1000));
    expect(_paintedCells(tester), isNot(firstFrame));

    await tester.pump(const Duration(milliseconds: 900));
    expect(_paintedCells(tester), firstFrame);
  });

  testWidgets('reduced motion holds the pet perfectly still', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet();

    await _pumpWindow(tester, viewModel, disableAnimations: true);
    final firstFrame = _paintedCells(tester);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(_paintedCells(tester), firstFrame);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_paintedCells(tester), firstFrame);
  });

  testWidgets('dress opens the picker with the current look selected', (
    tester,
  ) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet(variant: PetVariant.cat, outfit: PetOutfit.bow);

    await _pumpWindow(tester, viewModel);
    await tester.tap(find.text(AppStrings.petDress));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppStrings.petDressTitle), findsOneWidget);
    expect(find.text('${AppStrings.petVariantCat} ✓'), findsOneWidget);
    expect(find.text('${AppStrings.petOutfitBow} ✓'), findsOneWidget);
    expect(find.text(AppStrings.petVariantStar), findsOneWidget);
  });

  testWidgets('rename opens prefilled with the current name', (tester) async {
    final viewModel = _viewModel()
      ..isLoading = false
      ..pet = _pet(name: 'mochi');

    await _pumpWindow(tester, viewModel);
    await tester.tap(find.text(AppStrings.petRename));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppStrings.petRenameTitle), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'mochi',
    );
  });

  group('the story', () {
    testWidgets('lists events newest-first with a friendly line and time', (
      tester,
    ) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..pet = _pet()
        ..historyLoaded = true
        ..history = [
          PetEvent(
            id: 'ev3',
            coupleId: 'couple1',
            userId: 'userA',
            type: 'pet',
            created: _afternoon,
          ),
          PetEvent(
            id: 'ev2',
            coupleId: 'couple1',
            userId: 'userA',
            type: 'dress',
            created: _afternoon.subtract(const Duration(minutes: 2)),
          ),
          PetEvent(
            id: 'ev1',
            coupleId: 'couple1',
            userId: 'userB',
            type: 'feed',
            created: _afternoon.subtract(const Duration(days: 3)),
          ),
        ];

      await _pumpWindow(tester, viewModel);
      await tester.tap(find.text(AppStrings.petHistoryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.petHistoryTitle), findsOneWidget);
      expect(find.text('gave them a cuddle'), findsOneWidget);
      expect(find.text('changed how they look'), findsOneWidget);
      expect(find.text('gave them a snack ♡︎'), findsOneWidget);
      expect(find.text('just now'), findsOneWidget);
      expect(find.text('2m ago'), findsOneWidget);
      expect(find.text('aug 20'), findsOneWidget);
    });

    testWidgets('an unknown event type still gets a friendly fallback line', (
      tester,
    ) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..pet = _pet()
        ..historyLoaded = true
        ..history = [
          PetEvent(
            id: 'ev1',
            coupleId: 'couple1',
            userId: 'userA',
            type: 'hatched',
            created: _afternoon,
          ),
        ];

      await _pumpWindow(tester, viewModel);
      await tester.tap(find.text(AppStrings.petHistoryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('did something sweet for them ⋆'), findsOneWidget);
    });

    testWidgets('an empty story says so gently', (tester) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..pet = _pet()
        ..historyLoaded = true
        ..history = [];

      await _pumpWindow(tester, viewModel);
      await tester.tap(find.text(AppStrings.petHistoryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.petHistoryEmpty), findsOneWidget);
    });
  });
}
