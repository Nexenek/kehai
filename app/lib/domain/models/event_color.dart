import 'package:flutter/material.dart';

import '../../ui/core/theme/app_colors.dart';

/// Calendar-event pastel color. Mirrors `lib/domain/models/note_color.dart`
/// field-for-field (same `pink|lavender|mint|sky|butter` select values as
/// `calendar_events.color` on the server, see
/// server/migrations/11_calendar.go) — kept as its own small enum rather
/// than sharing `NoteColor` so the calendar feature doesn't reach into the
/// notes feature for something this small.
enum EventColor {
  pink,
  lavender,
  mint,
  sky,
  butter;

  static EventColor fromString(String? value) => EventColor.values.firstWhere(
    (c) => c.name == value,
    orElse: () => EventColor.pink,
  );

  /// Resolves against the current theme, same reasoning as
  /// `NoteColor.colorOf` — only [butter] is a fixed constant.
  Color colorOf(AppColors colors) => switch (this) {
    EventColor.pink => colors.chrome,
    EventColor.lavender => Color.lerp(colors.accent2, colors.surface, 0.55)!,
    EventColor.mint => colors.mint,
    EventColor.sky => colors.sky,
    EventColor.butter => butterConstant,
  };

  /// Same one-off pastel butter-yellow as `NoteColor.butterConstant`.
  static const butterConstant = Color(0xFFF7E8B0);
}
