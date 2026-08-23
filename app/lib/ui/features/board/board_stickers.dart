import 'package:flutter/foundation.dart';

/// A curated board sticker: a single glyph/kaomoji token plus a spoken
/// label (for the picker's accessibility semantics — never rely on the
/// glyph alone, per design-language.md's accessibility floor). Hearts carry
/// the ︎ text-presentation selector per the app_strings/mood.dart FE0E
/// convention (see e.g. AppStrings.trayOpen's heart and MoodCatalog's happy
/// kaomoji) — star/flower/sparkle/music-note don't need it, same as their
/// existing bare usage elsewhere in the app.
@immutable
class BoardSticker {
  const BoardSticker(this.glyph, this.label);

  final String glyph;
  final String label;
}

/// The small starter set offered by the sticker mini-picker (brief:
/// "large glyphs/kaomoji from a small curated picker — hearts, stars,
/// kaomoji, flowers"). Order is the order they appear in the picker grid.
class BoardStickerCatalog {
  const BoardStickerCatalog._();

  static const List<BoardSticker> all = [
    BoardSticker('♥︎', 'heart'),
    BoardSticker('★', 'star'),
    BoardSticker('✿', 'flower'),
    BoardSticker('✧', 'sparkle'),
    BoardSticker('(｡♥︎‿♥︎｡)', 'heart eyes'),
    BoardSticker('ヾ(＾-＾)ノ', 'excited'),
    BoardSticker('(´｡• ᵕ •｡`)', 'happy'),
    BoardSticker('♪', 'music note'),
  ];
}
