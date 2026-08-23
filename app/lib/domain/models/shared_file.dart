import 'package:flutter/foundation.dart';

/// A `shared_files` record — one entry in the couple's shared drive
/// (kb/features.md "Shared file storage"). Immutable server-side (no
/// update rule, same shape as doodles/instants — see
/// server/migrations/12_files.go): a file is either there or deleted,
/// never edited/relabeled in place. Re-upload instead.
@immutable
class SharedFile {
  const SharedFile({
    required this.id,
    required this.coupleId,
    required this.uploadedBy,
    required this.filename,
    required this.label,
    required this.created,
  });

  final String id;
  final String coupleId;
  final String uploadedBy;

  /// The raw stored filename (PocketBase appends a random suffix on
  /// upload) — needed to build the download URL; see
  /// `SharedFileRepository.downloadUrl`/`sharedFileDownloadUrl`. Also the
  /// one field guaranteed to still carry the real extension even if
  /// [label] gets edited away from it later, so [extension] reads from
  /// here rather than from [label].
  final String filename;

  /// Defaults to the originally-picked filename app-side at upload time
  /// (see `FilesViewModel.upload`) — a distinct field from [filename] so a
  /// future relabel-without-reupload flow stays possible without touching
  /// the underlying file.
  final String label;
  final DateTime created;

  /// What the list row shows — falls back to the raw filename if [label]
  /// is somehow empty (e.g. a record created directly against the API).
  String get displayLabel => label.isNotEmpty ? label : filename;

  /// Lowercase extension with no leading dot, used for the type glyph
  /// (`file_type_glyph.dart`). Empty for an extensionless filename.
  String get extension {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }
}
