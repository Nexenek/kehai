import 'package:flutter/foundation.dart';

import 'note_color.dart';

/// A `notes` record — a shared sticky note on "our desktop".
@immutable
class Note {
  const Note({
    required this.id,
    required this.coupleId,
    this.title = '',
    this.body = '',
    this.color = NoteColor.pink,
    this.pinned = false,
  });

  final String id;
  final String coupleId;
  final String title;
  final String body;
  final NoteColor color;
  final bool pinned;

  Note copyWith({
    String? title,
    String? body,
    NoteColor? color,
    bool? pinned,
  }) => Note(
    id: id,
    coupleId: coupleId,
    title: title ?? this.title,
    body: body ?? this.body,
    color: color ?? this.color,
    pinned: pinned ?? this.pinned,
  );
}
