import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/pet.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';
import 'package:couples_app/ui/features/pet/pet_painter.dart';
import 'package:couples_app/ui/features/pet/pet_state.dart';

const _colors = AppColors.light;

List<Color?> _cells({
  PetVariant variant = PetVariant.blob,
  PetOutfit outfit = PetOutfit.none,
  PetExpression expression = PetExpression.happy,
  bool blushing = false,
  int bob = 0,
}) => buildPetCells(
  variant: variant,
  outfit: outfit,
  expression: expression,
  blushing: blushing,
  colors: _colors,
  bob: bob,
);

Color? _at(List<Color?> cells, int x, int y) => cells[y * petGridSize + x];

int _countOf(List<Color?> cells, Color color) =>
    cells.where((c) => c == color).length;

void main() {
  group('sprite sheets', () {
    test('every variant is a well-formed 16x16 grid', () {
      for (final variant in PetVariant.values) {
        final sprite = petSpriteFor(variant);
        expect(sprite.rows.length, petGridSize, reason: '$variant rows');
        for (final row in sprite.rows) {
          expect(row.length, petGridSize, reason: '$variant row "$row"');
        }
      }
    });

    test('every variant leaves the bottom two rows clear for the bob', () {
      for (final variant in PetVariant.values) {
        final sprite = petSpriteFor(variant);
        for (var y = petGridSize - 2; y < petGridSize; y++) {
          for (var x = 0; x < petGridSize; x++) {
            expect(sprite.isBody(x, y), isFalse, reason: '$variant ($x,$y)');
          }
        }
      }
    });

    test('face anchors sit on the body so no feature floats in space', () {
      for (final variant in PetVariant.values) {
        final sprite = petSpriteFor(variant);
        for (final x in [3, 4, 11, 12]) {
          expect(
            sprite.isBody(x, sprite.eyeRow) &&
                sprite.isBody(x, sprite.eyeRow + 1),
            isTrue,
            reason: '$variant eye cell $x',
          );
        }
        for (final x in [6, 7, 8, 9]) {
          expect(
            sprite.isBody(x, sprite.mouthRow) &&
                sprite.isBody(x, sprite.mouthRow + 1),
            isTrue,
            reason: '$variant mouth cell $x',
          );
        }
      }
    });
  });

  group('composition', () {
    test('each variant paints its own body color, plus an ink outline', () {
      for (final variant in PetVariant.values) {
        final cells = _cells(variant: variant);
        expect(
          _countOf(cells, petBodyColor(variant, _colors)),
          greaterThan(40),
          reason: '$variant body',
        );
        expect(_countOf(cells, _colors.ink), greaterThan(10));
      }
    });

    test('the outline only fills empty cells next to filled ones', () {
      final cells = _cells();
      final sprite = petSpriteFor(PetVariant.blob);
      // A far corner touches nothing and stays clear.
      expect(_at(cells, 0, 15), isNull);
      // The cell directly above the blob's crown is outline, not body.
      final topRow = sprite.rows.indexWhere((row) => row.contains('#'));
      expect(_at(cells, 7, topRow), petBodyColor(PetVariant.blob, _colors));
      expect(_at(cells, 7, topRow - 1), _colors.ink);
    });

    test('the bob frame shifts every cell down exactly one row', () {
      final still = _cells();
      final bobbed = _cells(bob: 1);
      for (var y = 0; y < petGridSize - 1; y++) {
        for (var x = 0; x < petGridSize; x++) {
          expect(
            _at(bobbed, x, y + 1),
            _at(still, x, y),
            reason: 'cell ($x,$y)',
          );
        }
      }
    });

    test('expressions differ from one another', () {
      final byExpression = {
        for (final expression in PetExpression.values)
          expression: _cells(expression: expression),
      };
      for (final a in PetExpression.values) {
        for (final b in PetExpression.values) {
          if (a == b) continue;
          expect(byExpression[a], isNot(byExpression[b]), reason: '$a vs $b');
        }
      }
    });

    test('sleeping closes the eyes into flat lash lines', () {
      final asleep = _cells(expression: PetExpression.sleepy);
      final sprite = petSpriteFor(PetVariant.blob);

      for (var dx = 0; dx < 3; dx++) {
        expect(_at(asleep, 3 + dx, sprite.eyeRow + 1), _colors.ink);
        expect(_at(asleep, 10 + dx, sprite.eyeRow + 1), _colors.ink);
        // Nothing above the lashes: the eye is shut, not staring.
        expect(_at(asleep, 3 + dx, sprite.eyeRow), isNot(_colors.ink));
      }
    });

    test('blush appears only when blushing, and lands on the body', () {
      final plain = _cells();
      final blushing = _cells(blushing: true);
      expect(_countOf(plain, _colors.warn), 0);
      expect(_countOf(blushing, _colors.warn), 4);
    });

    test('blush sits on the cheeks, never on a stray limb like the tail', () {
      for (final variant in PetVariant.values) {
        final sprite = petSpriteFor(variant);
        final cells = _cells(variant: variant, blushing: true);
        expect(_countOf(cells, _colors.warn), 4, reason: '$variant');

        // The face's own contiguous run of body cells — the cat's tail is a
        // separate run on the same row, and must not get blushed.
        var min = petGridSize ~/ 2;
        var max = min;
        while (sprite.isBody(min - 1, sprite.mouthRow)) {
          min--;
        }
        while (sprite.isBody(max + 1, sprite.mouthRow)) {
          max++;
        }

        for (var y = 0; y < petGridSize; y++) {
          for (var x = 0; x < petGridSize; x++) {
            if (_at(cells, x, y) != _colors.warn) continue;
            expect(y, sprite.mouthRow, reason: '$variant blush row');
            expect(x, inInclusiveRange(min, max), reason: '$variant blush col');
          }
        }
      }
    });

    test('each outfit adds cells the bare pet does not have', () {
      final bare = _cells();
      for (final outfit in PetOutfit.values.where((o) => o != PetOutfit.none)) {
        final dressed = _cells(outfit: outfit);
        expect(dressed, isNot(bare), reason: '$outfit');
      }
    });

    test('a crown sits above the head, not on the face', () {
      final sprite = petSpriteFor(PetVariant.blob);
      final crowned = _cells(outfit: PetOutfit.crown);
      // Band row is filled across the crown's width…
      for (var x = 5; x <= 10; x++) {
        expect(_at(crowned, x, sprite.crownRow + 1), isNotNull);
      }
      // …and the eyes are untouched.
      expect(_at(crowned, 4, sprite.eyeRow), _at(_cells(), 4, sprite.eyeRow));
    });

    test('the scarf only wraps cells that are actually body', () {
      for (final variant in PetVariant.values) {
        final sprite = petSpriteFor(variant);
        final scarfed = _cells(variant: variant, outfit: PetOutfit.scarf);
        var band = 0;
        for (var dy = 0; dy < 2; dy++) {
          for (var x = 0; x < petGridSize; x++) {
            final y = sprite.scarfRow + dy;
            if (_at(scarfed, x, y) == _colors.mint && y < petGridSize) {
              expect(sprite.isBody(x, y), isTrue, reason: '$variant ($x,$y)');
              band++;
            }
          }
        }
        expect(band, greaterThan(6), reason: '$variant scarf width');
      }
    });

    test('a crown on the lavender blob is not also lavender', () {
      final crowned = _cells(variant: PetVariant.blob, outfit: PetOutfit.crown);
      final sprite = petSpriteFor(PetVariant.blob);
      expect(
        _at(crowned, 6, sprite.crownRow + 1),
        isNot(petBodyColor(PetVariant.blob, _colors)),
      );
    });
  });

  group('PetPainter', () {
    test('repaints only when the cells actually changed', () {
      final a = PetPainter(_cells());
      final same = PetPainter(_cells());
      final different = PetPainter(_cells(expression: PetExpression.sleepy));

      expect(a.shouldRepaint(same), isFalse);
      expect(a.shouldRepaint(different), isTrue);
    });
  });
}
