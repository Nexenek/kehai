import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/note_color.dart';
import 'package:couples_app/ui/core/theme/app_colors.dart';

void main() {
  group('NoteColor.fromString', () {
    test('parses every valid select value', () {
      expect(NoteColor.fromString('pink'), NoteColor.pink);
      expect(NoteColor.fromString('lavender'), NoteColor.lavender);
      expect(NoteColor.fromString('mint'), NoteColor.mint);
      expect(NoteColor.fromString('sky'), NoteColor.sky);
      expect(NoteColor.fromString('butter'), NoteColor.butter);
    });

    test('unknown or null values fall back to pink', () {
      expect(NoteColor.fromString(null), NoteColor.pink);
      expect(NoteColor.fromString(''), NoteColor.pink);
      expect(NoteColor.fromString('chartreuse'), NoteColor.pink);
    });
  });

  group('NoteColor.colorOf', () {
    test('maps each color to its theme token (light theme)', () {
      expect(NoteColor.pink.colorOf(AppColors.light), AppColors.light.chrome);
      expect(NoteColor.mint.colorOf(AppColors.light), AppColors.light.mint);
      expect(NoteColor.sky.colorOf(AppColors.light), AppColors.light.sky);
    });

    test('butter is the fixed one-off constant in both themes', () {
      expect(NoteColor.butter.colorOf(AppColors.light), NoteColor.butterConstant);
      expect(NoteColor.butter.colorOf(AppColors.dark), NoteColor.butterConstant);
    });

    test('lavender is a distinct tint, not identical to chromeAlt or accent2', () {
      final lavender = NoteColor.lavender.colorOf(AppColors.light);
      expect(lavender, isNot(AppColors.light.chromeAlt));
      expect(lavender, isNot(AppColors.light.accent2));
    });

    test('every color resolves to a different value from the others (dark theme too)', () {
      final colors = NoteColor.values.map((c) => c.colorOf(AppColors.dark)).toSet();
      expect(colors.length, NoteColor.values.length);
    });
  });
}
