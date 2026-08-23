/// The pet is **drawn, not shipped** — no image assets, no sprite sheets.
/// Everything below is a chunky 16×16 pixel grid painted as flat rects with
/// nearest-neighbour crispness by construction (design-language.md:
/// "texture filtering OFF — nearest/point sampling everywhere or the
/// crispness dies"), scaled up to whatever box the widget gets.
///
/// Layers, painted in order: body silhouette → outfit → face → ink outline
/// (any empty cell touching a filled one). The outline is computed from the
/// final composite, so a crown or a bow gets outlined exactly like the body.
library;

import 'package:flutter/material.dart';

import '../../../domain/models/pet.dart';
import '../../core/theme/app_colors.dart';
import 'pet_state.dart';

/// The pet grid is 16×16 cells. Rows 14–15 are deliberately left clear in
/// every sprite so the one-cell "breathing" bob has somewhere to go without
/// clipping the outline.
const int petGridSize = 16;

/// One variant's silhouette plus the anchor points the shared face/outfit
/// code draws against.
@immutable
class PetSprite {
  const PetSprite({
    required this.rows,
    required this.eyeRow,
    required this.mouthRow,
    required this.crownRow,
    required this.bowRow,
    required this.bowCol,
    required this.scarfRow,
  });

  /// 16 strings of 16 chars: '#' = body, anything else = empty.
  final List<String> rows;

  /// Top row of the eyes (they're 1–2 cells tall).
  final int eyeRow;

  /// Top row of the mouth.
  final int mouthRow;

  /// Top row of the 2-row crown (points row, then band row).
  final int crownRow;

  /// Top-left cell of the 5×3 bow.
  final int bowRow;
  final int bowCol;

  /// Top row of the 2-row scarf band; the knot hangs two rows below.
  final int scarfRow;

  bool isBody(int x, int y) {
    if (x < 0 || x >= petGridSize || y < 0 || y >= petGridSize) return false;
    return rows[y][x] == '#';
  }
}

/// A round lump with a nearly flat base — the default, and the friendliest.
const _blob = PetSprite(
  rows: [
    '................',
    '.....######.....',
    '...##########...',
    '..############..',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '.##############.',
    '..############..',
    '................',
    '................',
  ],
  eyeRow: 6,
  mouthRow: 9,
  crownRow: 0,
  bowRow: 2,
  bowCol: 1,
  scarfRow: 11,
);

/// Two stepped ears and a little tail on the right.
const _cat = PetSprite(
  rows: [
    '..#..........#..',
    '..##........##..',
    '..###......###..',
    '..############..',
    '..############..',
    '..############..',
    '..############..',
    '..############..',
    '..############..',
    '..############.#',
    '..############.#',
    '..#############.',
    '..############..',
    '..############..',
    '................',
    '................',
  ],
  eyeRow: 6,
  mouthRow: 9,
  crownRow: 1,
  bowRow: 3,
  bowCol: 0,
  scarfRow: 11,
);

/// Five points, stepped — arms wide, two little legs.
const _star = PetSprite(
  rows: [
    '.......##.......',
    '.......##.......',
    '......####......',
    '.##############.',
    '.##############.',
    '..############..',
    '..############..',
    '..############..',
    '...##########...',
    '...##########...',
    '..####....####..',
    '.####......####.',
    '.###........###.',
    '................',
    '................',
    '................',
  ],
  eyeRow: 6,
  mouthRow: 8,
  crownRow: 0,
  bowRow: 5,
  bowCol: 1,
  scarfRow: 10,
);

PetSprite petSpriteFor(PetVariant variant) => switch (variant) {
  PetVariant.blob => _blob,
  PetVariant.cat => _cat,
  PetVariant.star => _star,
};

/// On-palette body fills (design-language.md — no ad-hoc colors).
Color petBodyColor(PetVariant variant, AppColors colors) => switch (variant) {
  PetVariant.blob => colors.accent2,
  PetVariant.cat => colors.chrome,
  PetVariant.star => colors.sky,
};

/// Crown picks the token the body isn't wearing, so a lavender blob doesn't
/// get a lavender crown.
Color _crownColor(PetVariant variant, AppColors colors) =>
    variant == PetVariant.blob ? colors.mint : colors.accent2;

/// Builds the finished 16×16 cell grid (row-major, `y * 16 + x`), null where
/// nothing is drawn. Split out from the painter so the composition is
/// unit-testable without goldens.
///
/// [bob] shifts everything down by that many cells — the second frame of the
/// two-frame idle breathe.
List<Color?> buildPetCells({
  required PetVariant variant,
  required PetOutfit outfit,
  required PetExpression expression,
  required bool blushing,
  required AppColors colors,
  int bob = 0,
}) {
  final sprite = petSpriteFor(variant);
  final cells = List<Color?>.filled(petGridSize * petGridSize, null);

  void put(int x, int y, Color color) {
    final shifted = y + bob;
    if (x < 0 || x >= petGridSize || shifted < 0 || shifted >= petGridSize) {
      return;
    }
    cells[shifted * petGridSize + x] = color;
  }

  // 1. Body.
  final bodyColor = petBodyColor(variant, colors);
  for (var y = 0; y < petGridSize; y++) {
    for (var x = 0; x < petGridSize; x++) {
      if (sprite.isBody(x, y)) put(x, y, bodyColor);
    }
  }

  // 2. Outfit, on top of the body.
  switch (outfit) {
    case PetOutfit.none:
      break;
    case PetOutfit.bow:
      // A ribbon bow: two loops meeting at a knot.
      const bow = ['##.##', '.###.', '##.##'];
      for (var dy = 0; dy < bow.length; dy++) {
        for (var dx = 0; dx < bow[dy].length; dx++) {
          if (bow[dy][dx] == '#') {
            put(sprite.bowCol + dx, sprite.bowRow + dy, colors.accent);
          }
        }
      }
    case PetOutfit.scarf:
      // Two rows wrapped around whatever the silhouette is at that height,
      // so it fits every variant without per-variant widths.
      var knotCol = -1;
      for (var dy = 0; dy < 2; dy++) {
        final y = sprite.scarfRow + dy;
        for (var x = 0; x < petGridSize; x++) {
          if (sprite.isBody(x, y)) {
            put(x, y, colors.mint);
            if (knotCol < 0) knotCol = x + 2;
          }
        }
      }
      if (knotCol >= 0) {
        put(knotCol, sprite.scarfRow + 2, colors.mint);
        put(knotCol + 1, sprite.scarfRow + 2, colors.mint);
      }
    case PetOutfit.crown:
      final crown = _crownColor(variant, colors);
      for (final x in [5, 7, 9]) {
        put(x, sprite.crownRow, crown);
      }
      for (var x = 5; x <= 10; x++) {
        put(x, sprite.crownRow + 1, crown);
      }
  }

  // 3. Face. Eyes are symmetric about the grid centre (col 3 mirrors 12).
  final ink = colors.ink;
  final eyeRow = sprite.eyeRow;
  switch (expression) {
    case PetExpression.happy:
      // ^ ^ — a caret per eye.
      for (final left in [3, 10]) {
        put(left, eyeRow + 1, ink);
        put(left + 1, eyeRow, ink);
        put(left + 2, eyeRow + 1, ink);
      }
    case PetExpression.content:
      for (final left in [3, 11]) {
        put(left, eyeRow, ink);
        put(left + 1, eyeRow, ink);
        put(left, eyeRow + 1, ink);
        put(left + 1, eyeRow + 1, ink);
      }
    case PetExpression.wistful:
      // Half-lidded, looking a little downward.
      for (final left in [3, 11]) {
        put(left, eyeRow + 1, ink);
        put(left + 1, eyeRow + 1, ink);
      }
    case PetExpression.sleepy:
      // Closed: a flat lash line per eye. The "zzZ" rides in the state line
      // under the sprite rather than on the grid — a floating z has nowhere
      // clean to sit in 16×16 next to a wide silhouette without the outline
      // pass welding it to the pet's head.
      for (final left in [3, 10]) {
        for (var dx = 0; dx < 3; dx++) {
          put(left + dx, eyeRow + 1, ink);
        }
      }
  }

  final mouthRow = sprite.mouthRow;
  switch (expression) {
    case PetExpression.happy:
      put(6, mouthRow, ink);
      put(7, mouthRow + 1, ink);
      put(8, mouthRow + 1, ink);
      put(9, mouthRow, ink);
    case PetExpression.content:
      put(7, mouthRow + 1, ink);
      put(8, mouthRow + 1, ink);
    case PetExpression.wistful:
      // A small open "o" — wistful, not sad.
      put(7, mouthRow, ink);
      put(8, mouthRow, ink);
      put(7, mouthRow + 1, ink);
      put(8, mouthRow + 1, ink);
    case PetExpression.sleepy:
      put(7, mouthRow + 1, ink);
      put(8, mouthRow + 1, ink);
  }

  // 4. Blush, on the cheeks: the ends of the *contiguous* body run through
  // the middle of the mouth row — following the run rather than the row's
  // extremes keeps it off detached bits like the cat's tail.
  if (blushing) {
    const centre = petGridSize ~/ 2;
    var min = centre;
    var max = centre;
    if (sprite.isBody(centre, mouthRow)) {
      while (sprite.isBody(min - 1, mouthRow)) {
        min--;
      }
      while (sprite.isBody(max + 1, mouthRow)) {
        max++;
      }
    }
    if (max - min >= 6) {
      put(min, mouthRow, colors.warn);
      put(min + 1, mouthRow, colors.warn);
      put(max - 1, mouthRow, colors.warn);
      put(max, mouthRow, colors.warn);
    }
  }

  // 5. Ink outline: every empty cell that touches a filled one. Runs on the
  // composite (already bobbed), so it hugs the outfit too.
  final outlined = List<Color?>.of(cells);
  for (var y = 0; y < petGridSize; y++) {
    for (var x = 0; x < petGridSize; x++) {
      if (cells[y * petGridSize + x] != null) continue;
      final touching =
          (x > 0 && cells[y * petGridSize + x - 1] != null) ||
          (x < petGridSize - 1 && cells[y * petGridSize + x + 1] != null) ||
          (y > 0 && cells[(y - 1) * petGridSize + x] != null) ||
          (y < petGridSize - 1 && cells[(y + 1) * petGridSize + x] != null);
      if (touching) outlined[y * petGridSize + x] = ink;
    }
  }
  return outlined;
}

/// Paints a prebuilt cell grid as flat, grid-snapped rects.
class PetPainter extends CustomPainter {
  const PetPainter(this.cells);

  final List<Color?> cells;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / petGridSize;
    if (cell <= 0) return;
    final dx = (size.width - cell * petGridSize) / 2;
    final dy = (size.height - cell * petGridSize) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < petGridSize; y++) {
      for (var x = 0; x < petGridSize; x++) {
        final color = cells[y * petGridSize + x];
        if (color == null) continue;
        paint.color = color;
        // +0.5 on the size closes hairline seams between cells at
        // fractional scales without softening the pixel look.
        canvas.drawRect(
          Rect.fromLTWH(dx + x * cell, dy + y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PetPainter oldDelegate) {
    if (oldDelegate.cells.length != cells.length) return true;
    for (var i = 0; i < cells.length; i++) {
      if (oldDelegate.cells[i] != cells[i]) return true;
    }
    return false;
  }
}
