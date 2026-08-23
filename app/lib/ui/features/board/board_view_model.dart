import 'dart:math';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/board_repository.dart';
import '../../../domain/models/board_item.dart';
import '../../../domain/models/note_color.dart';
import 'board_drag_logic.dart';

/// Drives the shared board (kb/features.md "Shared board"): loads the
/// couple's items, keeps them fresh via realtime create/update/delete (a
/// partner's moves arrive as `update` and reconcile in-place), and owns the
/// drag lifecycle — local-only position/z updates mid-drag, one persisted
/// write at drag end (see `board_drag_logic.dart`'s `shouldPersistBoardDrag`).
///
/// Self-contained under `ui/features/board` — this batch builds the feature
/// but does NOT wire it into the home tray/layout (another agent owns that
/// composition this round, same as `InstantsWindow`); a caller just needs a
/// [BoardViewModel] wired to real repositories.
class BoardViewModel extends ChangeNotifier {
  BoardViewModel({
    required AuthRepository authRepository,
    required BoardRepository boardRepository,
    Random? random,
  }) : _authRepository = authRepository,
       _boardRepository = boardRepository,
       _random = random ?? Random();

  final AuthRepository _authRepository;
  final BoardRepository _boardRepository;
  final Random _random;

  bool isLoading = true;
  List<BoardItem> items = const [];

  UnsubscribeFunc? _unsub;
  String? _draggingId;

  String? get _coupleId => _authRepository.coupleId;

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        items = await _boardRepository.fetchAll(coupleId);
      } catch (_) {
        // Leave the board empty — it still renders its empty state.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _boardRepository.subscribe((action, item) {
      if (item.coupleId != _coupleId) return;
      if (action == 'delete') {
        items = items.where((i) => i.id != item.id).toList();
      } else {
        final idx = items.indexWhere((i) => i.id == item.id);
        // A partner's move arrives here too (as `update`) — replacing in
        // place is exactly the reconcile a live move needs.
        items = idx == -1
            ? [...items, item]
            : (List.of(items)..[idx] = item);
      }
      notifyListeners();
    });
  }

  Future<void> addNote({required String text, required NoteColor color}) {
    final coupleId = _coupleId;
    final trimmed = text.trim();
    if (coupleId == null || trimmed.isEmpty) return Future.value();
    final pos = _dropPosition();
    return _boardRepository.createNote(
      coupleId: coupleId,
      text: trimmed,
      x: pos.dx,
      y: pos.dy,
      rot: randomBoardTilt(_random),
      z: nextBoardZ(items.map((i) => i.z)),
      color: color,
    );
  }

  Future<void> addSticker(String glyph) {
    final coupleId = _coupleId;
    if (coupleId == null || glyph.isEmpty) return Future.value();
    final pos = _dropPosition();
    return _boardRepository.createSticker(
      coupleId: coupleId,
      sticker: glyph,
      x: pos.dx,
      y: pos.dy,
      rot: randomBoardTilt(_random),
      z: nextBoardZ(items.map((i) => i.z)),
    );
  }

  Future<void> addPhoto({
    required Uint8List imageBytes,
    required String filename,
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    final pos = _dropPosition();
    return _boardRepository.createPhoto(
      coupleId: coupleId,
      imageBytes: imageBytes,
      filename: filename,
      x: pos.dx,
      y: pos.dy,
      rot: randomBoardTilt(_random),
      z: nextBoardZ(items.map((i) => i.z)),
    );
  }

  /// Center-ish with a little jitter, so several quick adds don't stack
  /// exactly on top of one another before anyone's dragged them apart.
  Offset _dropPosition() {
    final jitterX = (_random.nextDouble() - 0.5) * 0.2;
    final jitterY = (_random.nextDouble() - 0.5) * 0.2;
    return clampBoardPosition(Offset(0.5 + jitterX, 0.5 + jitterY));
  }

  // --- drag -----------------------------------------------------------

  /// Routes one drag lifecycle event for [id]. `start`/`update` only touch
  /// local state (instant visual feedback, no network); only `end` persists
  /// — see `board_drag_logic.dart`'s `shouldPersistBoardDrag`.
  Future<void> handleDrag({
    required String id,
    required BoardDragPhase phase,
    Offset pixelDelta = Offset.zero,
    Size boardSize = Size.zero,
  }) async {
    switch (phase) {
      case BoardDragPhase.start:
        _beginDrag(id);
      case BoardDragPhase.update:
        _updateDragPosition(id, pixelDelta, boardSize);
      case BoardDragPhase.cancel:
        _draggingId = null;
      case BoardDragPhase.end:
        if (shouldPersistBoardDrag(phase)) await _endDrag(id);
    }
  }

  void _beginDrag(String id) {
    _draggingId = id;
    final idx = items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final z = nextBoardZ(items.map((i) => i.z));
    items = List.of(items)..[idx] = items[idx].copyWith(z: z);
    notifyListeners();
  }

  void _updateDragPosition(String id, Offset pixelDelta, Size boardSize) {
    final idx = items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final current = items[idx];
    final newPos = dragBoardPosition(
      start: Offset(current.x, current.y),
      pixelDelta: pixelDelta,
      boardSize: boardSize,
    );
    items = List.of(items)
      ..[idx] = current.copyWith(x: newPos.dx, y: newPos.dy);
    notifyListeners();
  }

  Future<void> _endDrag(String id) async {
    if (_draggingId != id) return;
    _draggingId = null;
    final idx = items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = items[idx];
    await _boardRepository.updatePosition(
      item.id,
      x: item.x,
      y: item.y,
      z: item.z,
    );
  }

  Future<void> deleteItem(String id) async {
    items = items.where((i) => i.id != id).toList();
    notifyListeners();
    await _boardRepository.delete(id);
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
