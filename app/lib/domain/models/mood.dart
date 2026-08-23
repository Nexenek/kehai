import 'package:flutter/material.dart';

import '../../ui/core/theme/app_colors.dart';

/// A mood option: kaomoji + name + a palette color (never emoji, never
/// color alone — design-language.md: "Moods are kaomoji + color, not
/// emoji" and the accessibility floor requires icon+text, not color alone).
@immutable
class Mood {
  const Mood({
    required this.id,
    required this.kaomoji,
    required this.label,
    required this.colorOf,
  });

  final String id;
  final String kaomoji;
  final String label;

  /// Resolves the mood's accent color against the current theme so light
  /// and dark palettes both stay on-token.
  final Color Function(AppColors colors) colorOf;
}

/// The ~10 starter moods. Order is the order they appear in the picker
/// grid.
class MoodCatalog {
  const MoodCatalog._();

  static const List<Mood> all = [
    Mood(id: 'happy', kaomoji: '(´｡• ᵕ •｡`) ♡', label: 'happy', colorOf: _mint),
    Mood(
      id: 'sleepy',
      kaomoji: '(￣o￣) zzZ',
      label: 'sleepy',
      colorOf: _accent2,
    ),
    Mood(id: 'excited', kaomoji: 'ヾ(＾-＾)ノ', label: 'excited', colorOf: _accent),
    Mood(id: 'sad', kaomoji: '(｡•́︿•̀｡)', label: 'sad', colorOf: _sky),
    Mood(id: 'hungry', kaomoji: '(｡•ˇ‸ˇ•｡)', label: 'hungry', colorOf: _warn),
    Mood(id: 'gaming', kaomoji: '(⌐■_■)', label: 'gaming', colorOf: _accent),
    Mood(
      id: 'working',
      kaomoji: '(-_-;)',
      label: 'working',
      colorOf: _chromeAlt,
    ),
    Mood(
      id: 'missing_you',
      kaomoji: '(っ˘̩╭╮˘̩)っ',
      label: 'missing you',
      colorOf: _warn,
    ),
    Mood(id: 'cozy', kaomoji: '(｡- ｡)', label: 'cozy', colorOf: _mint),
    Mood(id: 'meh', kaomoji: '(－ω－)', label: 'meh', colorOf: _chromeAlt),
  ];

  static Mood byId(String? id) {
    return all.firstWhere((m) => m.id == id, orElse: () => all.first);
  }

  static Color _mint(AppColors c) => c.mint;
  static Color _sky(AppColors c) => c.sky;
  static Color _warn(AppColors c) => c.warn;
  static Color _accent(AppColors c) => c.accent;
  static Color _accent2(AppColors c) => c.accent2;
  static Color _chromeAlt(AppColors c) => c.chromeAlt;
}
