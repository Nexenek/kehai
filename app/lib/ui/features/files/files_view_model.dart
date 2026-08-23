import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/shared_file_repository.dart';
import '../../../domain/models/shared_file.dart';

/// Drives the shared-files window: loads the couple's drive, keeps it
/// fresh via realtime create/delete, and owns the upload/delete lifecycle.
/// Same reconcile-by-action pattern as `InstantsViewModel`/`BoardViewModel`.
///
/// Self-contained under `ui/features/files` — this batch builds the
/// feature but does NOT wire it into the home tray/layout (another agent
/// owns that composition this round, same as `InstantsWindow`/
/// `BoardWindow`); a caller just needs a [FilesViewModel] wired to real
/// repositories.
class FilesViewModel extends ChangeNotifier {
  FilesViewModel({
    required AuthRepository authRepository,
    required SharedFileRepository fileRepository,
  }) : _authRepository = authRepository,
       _fileRepository = fileRepository;

  final AuthRepository _authRepository;
  final SharedFileRepository _fileRepository;

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  List<SharedFile> files = const [];

  int _page = 1;
  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;
  String get myUserId => _authRepository.currentUserId;

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        final result = await _fileRepository.list(coupleId, page: 1);
        files = result.items;
        hasMore = result.hasMore;
        _page = 1;
      } catch (_) {
        // Leave the list empty — the window still renders its empty state
        // (also covers the server collection not existing yet).
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _fileRepository.subscribe((action, file) {
      if (file.coupleId != _coupleId) return;
      if (action == 'delete') {
        files = files.where((f) => f.id != file.id).toList();
      } else if (!files.any((f) => f.id == file.id)) {
        files = [file, ...files]..sort((a, b) => b.created.compareTo(a.created));
      }
      notifyListeners();
    });
  }

  /// Fetches the next page and appends it, deduping against whatever
  /// realtime already delivered in the meantime — same shape as
  /// `InstantsViewModel.loadMore`.
  Future<void> loadMore() async {
    final coupleId = _coupleId;
    if (coupleId == null || !hasMore || isLoadingMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final result = await _fileRepository.list(coupleId, page: _page + 1);
      _page += 1;
      final existingIds = files.map((f) => f.id).toSet();
      files = [
        ...files,
        ...result.items.where((f) => !existingIds.contains(f.id)),
      ];
      hasMore = result.hasMore;
    } catch (_) {
      hasMore = false;
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Uploads a picked file. The caller (`files_window.dart`'s upload
  /// button, which owns its own busy/error state the same way
  /// `send_instant_dialog.dart` does) already did the ≤100MB check and
  /// knows [length] without reading the whole file into memory
  /// (`XFile.length()`), so this stays a pure pass-through to the
  /// repository's streaming upload — errors propagate to the caller rather
  /// than being swallowed here, matching `InstantsViewModel.send`.
  Future<void> upload({
    required Stream<List<int>> stream,
    required int length,
    required String filename,
    required String label,
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _fileRepository.create(
      coupleId: coupleId,
      uploadedBy: myUserId,
      stream: stream,
      length: length,
      filename: filename,
      label: label,
    );
  }

  /// Either partner may delete any file in the couple (contract: delete is
  /// couple-scoped, not author-scoped) — same as `InstantsViewModel`.
  Future<void> deleteFile(String id) async {
    files = files.where((f) => f.id != id).toList();
    notifyListeners();
    await _fileRepository.delete(id);
  }

  /// Resolves [file]'s protected, tokenized download URL. Returns null on
  /// failure (offline, token mint failed, file gone) rather than throwing,
  /// so the window can show an honest "couldn't open that" instead of
  /// crashing.
  Future<String?> downloadUrl(SharedFile file) async {
    try {
      return await _fileRepository.downloadUrl(file);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
