import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/instant_repository.dart';
import '../../../domain/models/instant.dart';

/// Drives the "instants" feed: a reverse-chronological photo grid,
/// paginated 30 at a time, kept fresh via realtime create/delete — same
/// reconcile-by-action pattern as `DoodleViewModel`/`NotesViewModel`.
///
/// Self-contained under `ui/features/instants` (rather than living beside
/// the other home view models) since this batch doesn't wire the feature
/// into the home screen — see the feature's top-level doc note in
/// `instants_window.dart`.
class InstantsViewModel extends ChangeNotifier {
  InstantsViewModel({
    required AuthRepository authRepository,
    required InstantRepository instantRepository,
  }) : _authRepository = authRepository,
       _instantRepository = instantRepository;

  final AuthRepository _authRepository;
  final InstantRepository _instantRepository;

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  List<Instant> instants = const [];

  int _page = 1;
  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;
  String get myUserId => _authRepository.currentUserId;

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        final result = await _instantRepository.list(coupleId, page: 1);
        instants = result.items;
        hasMore = result.hasMore;
        _page = 1;
      } catch (_) {
        // Leave the list empty — the window still renders its empty state
        // (also covers the server collection not existing yet).
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _instantRepository.subscribe((action, instant) {
      if (instant.coupleId != _coupleId) return;
      if (action == 'delete') {
        instants = instants.where((i) => i.id != instant.id).toList();
      } else if (!instants.any((i) => i.id == instant.id)) {
        instants = [instant, ...instants]
          ..sort((a, b) => b.created.compareTo(a.created));
      }
      notifyListeners();
    });
  }

  /// Fetches the next page and appends it, deduping against whatever
  /// realtime already delivered in the meantime.
  Future<void> loadMore() async {
    final coupleId = _coupleId;
    if (coupleId == null || !hasMore || isLoadingMore) return;
    isLoadingMore = true;
    notifyListeners();
    try {
      final result = await _instantRepository.list(coupleId, page: _page + 1);
      _page += 1;
      final existingIds = instants.map((i) => i.id).toSet();
      instants = [
        ...instants,
        ...result.items.where((i) => !existingIds.contains(i.id)),
      ];
      hasMore = result.hasMore;
    } catch (_) {
      hasMore = false;
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> send({
    required Uint8List imageBytes,
    required String filename,
    String caption = '',
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _instantRepository.create(
      coupleId: coupleId,
      authorId: myUserId,
      imageBytes: imageBytes,
      filename: filename,
      caption: caption,
    );
  }

  /// Either partner may delete any instant in the couple (contract: delete
  /// is couple-scoped, not author-scoped) — unlike `DoodleViewModel`, which
  /// only ever deletes "mine".
  Future<void> deleteInstant(String id) async {
    instants = instants.where((i) => i.id != id).toList();
    notifyListeners();
    await _instantRepository.delete(id);
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
