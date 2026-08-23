import 'package:flutter/foundation.dart';

/// A `countdowns` record — a shared date the couple is counting down to
/// (or looking back on, once it's passed).
@immutable
class Countdown {
  const Countdown({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.date,
    this.kaomoji = '',
  });

  final String id;
  final String coupleId;
  final String title;

  /// Date-only in spirit — stored as a PocketBase datetime, but every
  /// display/sort path treats it via date-only math (see
  /// `lib/domain/day_math.dart`).
  final DateTime date;

  /// Optional decorative kaomoji shown next to the title, e.g. "✈" or
  /// "(๑˃ᴗ˂)ﻭ".
  final String kaomoji;

  Countdown copyWith({String? title, DateTime? date, String? kaomoji}) =>
      Countdown(
        id: id,
        coupleId: coupleId,
        title: title ?? this.title,
        date: date ?? this.date,
        kaomoji: kaomoji ?? this.kaomoji,
      );
}
