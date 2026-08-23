import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/shared_file.dart';

/// Maps a raw `shared_files` [RecordModel] to a [SharedFile]. Split out as a
/// top-level function (see `instant_repository.dart`'s `instantFromRecord`
/// doc comment for why) so the mapping is unit-testable without a live
/// collection.
SharedFile sharedFileFromRecord(RecordModel r) => SharedFile(
  id: r.id,
  coupleId: r.get<String>('couple'),
  uploadedBy: r.get<String>('uploaded_by'),
  filename: r.get<String>('file'),
  label: r.get<String>('label', ''),
  created:
      DateTime.tryParse(r.get<String>('created'))?.toLocal() ?? DateTime.now(),
);

/// Builds a `shared_files` file's *protected* download URL given an
/// already-minted file [token] — pure string-building (like
/// `pb.files.getUrl` itself), split out from
/// [SharedFileRepository.downloadUrl] (which does the live token fetch) so
/// the URL shape is unit-testable without a server. Only [SharedFile.id]
/// and [SharedFile.filename] matter here; a bare `collectionName` is
/// enough for `pb.files.getUrl` to build the path (see `FileService.getURL`
/// in the pocketbase package — it prefers `collectionId` but falls back to
/// `collectionName`), so this doesn't need the full original [RecordModel]
/// kept around.
String sharedFileDownloadUrl(PocketBase pb, SharedFile file, String token) {
  final record = RecordModel({
    'id': file.id,
    'collectionName': 'shared_files',
  });
  return pb.files.getUrl(record, file.filename, token: token).toString();
}

/// One page of the reverse-chronological shared files list.
class SharedFilesPage {
  const SharedFilesPage({required this.items, required this.hasMore});

  final List<SharedFile> items;
  final bool hasMore;

  static const empty = SharedFilesPage(items: [], hasMore: false);
}

/// `shared_files` — the couple's shared drive (kb/features.md "Shared file
/// storage"). Couple-scoped visibility + "uploaded_by must be me" +
/// "either partner can delete" are enforced server-side (see
/// server/migrations/12_files.go); this repository just talks to the
/// collection. Immutable (no `update` — see [SharedFile]'s doc comment).
///
/// The file field is Protected server-side, so a plain `pb.files.getUrl`
/// isn't enough to actually fetch a file — [downloadUrl] mints a
/// short-lived file token first (`POST /api/files/token`) and bakes it
/// into the URL. See that method's doc comment for the full flow.
class SharedFileRepository {
  SharedFileRepository(this._pb);

  final PocketBase _pb;

  static const perPage = 30;

  /// Mirrors the server's cap (server/migrations/12_files.go's
  /// `MaxSize: 100 << 20`) so the app can reject an oversized pick before
  /// spending any upload bandwidth on it — see
  /// `shared_file_upload_limits.dart`.
  static const maxUploadBytes = 100 << 20;

  SharedFile _fromRecord(RecordModel r) => sharedFileFromRecord(r);

  /// The most recent [page] of shared files for [coupleId], newest first.
  Future<SharedFilesPage> list(String coupleId, {int page = 1}) async {
    try {
      final result = await _pb
          .collection('shared_files')
          .getList(
            page: page,
            perPage: perPage,
            filter: 'couple = "$coupleId"',
            sort: '-created',
          );
      return SharedFilesPage(
        items: result.items.map(_fromRecord).toList(),
        hasMore: result.page < result.totalPages,
      );
    } on ClientException catch (e) {
      if (e.statusCode == 404) return SharedFilesPage.empty;
      rethrow;
    }
  }

  /// Uploads a file from a byte [stream] of known [length] — never buffers
  /// the whole thing into memory first (the SDK's underlying
  /// `http.MultipartFile` streams it straight into the multipart body), so
  /// this stays cheap even near the 100MB cap. [uploadedBy] must be the
  /// caller's own user id — the server rejects anything else. [label]
  /// defaults to the picked filename app-side (see `FilesViewModel.upload`)
  /// rather than being enforced server-side, so a relabel-only flow stays
  /// possible later without touching the file itself.
  Future<void> create({
    required String coupleId,
    required String uploadedBy,
    required Stream<List<int>> stream,
    required int length,
    required String filename,
    String label = '',
  }) {
    return _pb
        .collection('shared_files')
        .create(
          body: {'couple': coupleId, 'uploaded_by': uploadedBy, 'label': label},
          files: [
            http.MultipartFile('file', stream, length, filename: filename),
          ],
        );
  }

  Future<void> delete(String id) => _pb.collection('shared_files').delete(id);

  /// Mints a fresh, short-lived file token (`POST /api/files/token` —
  /// requires the caller's normal auth) and bakes it into [file]'s
  /// download URL. The token, not the caller's session, is what
  /// authorizes the actual `GET /api/files/...` fetch: PocketBase
  /// re-checks the collection's ViewRule against the token's auth record
  /// on every download (server/migrations/12_files.go's doc comment; see
  /// also `server/files_test.go`'s `TestSharedFileProtectedAccess`), so
  /// this has to be a fresh async call per download rather than a URL
  /// built once and cached — a token is meant to be short-lived.
  Future<String> downloadUrl(SharedFile file) async {
    final token = await _pb.files.getToken();
    return sharedFileDownloadUrl(_pb, file, token);
  }

  /// Fires on create/delete alike (files are immutable, so no `update`
  /// action ever arrives) — see `DoodleRepository.subscribe` for why the
  /// raw action string is exposed. Swallows a subscribe failure into a
  /// no-op unsubscribe, matching the other realtime-collection
  /// repositories' "nothing yet" handling.
  Future<UnsubscribeFunc> subscribe(
    void Function(String action, SharedFile file) onChange,
  ) async {
    try {
      return await _pb.collection('shared_files').subscribe('*', (e) {
        if (e.record != null) onChange(e.action, _fromRecord(e.record!));
      });
    } catch (_) {
      return () async {};
    }
  }
}
