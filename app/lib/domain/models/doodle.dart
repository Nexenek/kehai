import 'package:flutter/foundation.dart';

/// A `doodles` record — a little PNG one partner drew for the other.
/// Immutable server-side (no update endpoint): a doodle is either there or
/// deleted, never edited.
@immutable
class Doodle {
  const Doodle({
    required this.id,
    required this.coupleId,
    required this.authorId,
    required this.imageUrl,
    required this.created,
  });

  final String id;
  final String coupleId;
  final String authorId;

  /// Absolute PB file URL (see [DoodleRepository]'s use of `pb.files.getUrl`).
  final String imageUrl;
  final DateTime created;
}
