import 'package:flutter/foundation.dart';

/// An `instants` record — a quick photo one partner shares through the day
/// (kb/contracts.md "Instants"). Immutable server-side (no update rule,
/// same shape as `doodles`): an instant is either there or deleted, never
/// edited. Unlike a doodle, either partner may delete any instant in the
/// couple (contract: "delete couple-scoped", not author-scoped).
@immutable
class Instant {
  const Instant({
    required this.id,
    required this.coupleId,
    required this.authorId,
    required this.imageUrl,
    required this.caption,
    required this.created,
  });

  final String id;
  final String coupleId;
  final String authorId;

  /// Absolute PB file URL (see [InstantRepository]'s use of
  /// `pb.files.getUrl`).
  final String imageUrl;

  /// Optional, ≤140 chars (enforced client-side by
  /// `instant_image_prep.isCaptionWithinLimit` and server-side by the
  /// collection schema).
  final String caption;
  final DateTime created;
}
