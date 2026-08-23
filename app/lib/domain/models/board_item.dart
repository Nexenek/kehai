import 'package:flutter/foundation.dart';

import 'note_color.dart';

/// What a `board_items` record represents on the shared board
/// (kb/features.md "Shared board").
enum BoardItemType {
  note,
  photo,
  sticker;

  static BoardItemType fromString(String value) => BoardItemType.values
      .firstWhere((t) => t.name == value, orElse: () => BoardItemType.note);
}

/// A `board_items` record — one sticky note, photo, or sticker pinned to
/// the shared, freeform pinboard both partners arrange together
/// (kb/design-language.md's desktop-metaphor "power-user wink: they
/// genuinely rearrange"). Couple-scoped shared ownership: either partner
/// may move or delete any item (server/migrations/8_board.go's `shared`
/// rule), so there's deliberately no author field.
@immutable
class BoardItem {
  const BoardItem({
    required this.id,
    required this.coupleId,
    required this.type,
    this.text = '',
    this.imageUrl,
    this.sticker = '',
    required this.x,
    required this.y,
    this.rot = 0,
    this.z = 0,
    this.color = NoteColor.pink,
  });

  final String id;
  final String coupleId;
  final BoardItemType type;

  /// Note body — only meaningful when [type] is [BoardItemType.note].
  final String text;

  /// Absolute PB file URL — only set when [type] is [BoardItemType.photo].
  final String? imageUrl;

  /// A single glyph/kaomoji token — only meaningful when [type] is
  /// [BoardItemType.sticker].
  final String sticker;

  /// Normalized board position, 0..1 on both axes (top-left origin).
  final double x;
  final double y;

  /// Hand-placed tilt in degrees, -30..30.
  final double rot;

  /// Stacking order — higher paints on top; bumped past the current max on
  /// grab ("bring to front").
  final double z;

  /// Sticky-note pastel — only meaningful when [type] is
  /// [BoardItemType.note] (photos and stickers ignore it).
  final NoteColor color;

  BoardItem copyWith({double? x, double? y, double? rot, double? z}) =>
      BoardItem(
        id: id,
        coupleId: coupleId,
        type: type,
        text: text,
        imageUrl: imageUrl,
        sticker: sticker,
        x: x ?? this.x,
        y: y ?? this.y,
        rot: rot ?? this.rot,
        z: z ?? this.z,
        color: color,
      );
}
