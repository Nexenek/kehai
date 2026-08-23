import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/art_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../domain/art_scene.dart';

/// Drives the art manager: the couple's layers per slot, the live preview
/// combo, and every edit the artist can make.
///
/// Self-contained under `ui/features/art` (like the instants/board view
/// models) since this batch builds the feature but doesn't wire it into the
/// home tray/layout — see the note at the top of `art_window.dart`.
class ArtViewModel extends ChangeNotifier {
  ArtViewModel({
    required AuthRepository authRepository,
    required ArtRepository artRepository,
  }) : _authRepository = authRepository,
       _artRepository = artRepository;

  final AuthRepository _authRepository;
  final ArtRepository _artRepository;

  bool isLoading = true;
  List<ArtLayer> layers = const [];

  /// The preview combo — the artist's feedback loop: "if they felt sleepy
  /// and were listening to music, what would they see?"
  String previewMoodId = 'happy';
  String? previewAmbientKind;

  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;

  /// What the partner window would show for the previewed combo.
  List<ArtLayer> get previewScene => resolveArtScene(
    layers,
    moodId: previewMoodId,
    ambientKind: previewAmbientKind,
  );

  /// True once there's at least one `base` layer — until then no
  /// combination can produce a scene, and the manager says so plainly
  /// rather than leaving the artist to guess.
  bool get hasBaseLayer => layers.any((l) => l.slot == ArtSlot.base);

  List<ArtLayer> layersIn(ArtSlot slot) => artLayersInSlot(layers, slot);

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        layers = await _artRepository.fetchAll(coupleId);
      } catch (_) {
        // Leave it empty — the window renders its empty state, which also
        // covers a server that hasn't run migration 10 yet.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _artRepository.subscribe((action, layer) {
      if (layer.coupleId != _coupleId) return;
      if (action == 'delete') {
        layers = layers.where((l) => l.id != layer.id).toList();
      } else {
        layers = [...layers.where((l) => l.id != layer.id), layer];
      }
      notifyListeners();
    });
  }

  void setPreviewMood(String moodId) {
    previewMoodId = moodId;
    notifyListeners();
  }

  /// Null = "nothing in particular", i.e. the ambient dimension sits out of
  /// the match entirely — which is genuinely what happens when the partner
  /// has no device reporting anything.
  void setPreviewAmbient(String? kind) {
    previewAmbientKind = kind;
    notifyListeners();
  }

  /// Uploads a new drawing into [slot], placed at the end of that slot's
  /// list. Returns false if there's no couple yet or the upload failed —
  /// the dialog turns that into honest copy rather than a stack trace.
  Future<bool> addLayer({
    required ArtSlot slot,
    required String name,
    required Uint8List imageBytes,
    required String filename,
    ArtConditions conditions = ArtConditions.any,
  }) async {
    final coupleId = _coupleId;
    if (coupleId == null) return false;
    try {
      await _artRepository.create(
        coupleId: coupleId,
        slot: slot,
        name: name,
        imageBytes: imageBytes,
        filename: filename,
        conditions: conditions,
        sort: _nextSortIn(slot),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  double _nextSortIn(ArtSlot slot) {
    final inSlot = layersIn(slot);
    if (inSlot.isEmpty) return 0;
    return inSlot.last.sort + 1;
  }

  /// Renames / re-conditions a layer. Optimistic: the list updates before
  /// the round trip, and realtime reconciles whatever the server actually
  /// stored.
  Future<void> saveLayer(
    ArtLayer layer, {
    required String name,
    required ArtConditions conditions,
  }) async {
    _replace(layer.copyWith(name: name, conditions: conditions));
    notifyListeners();
    try {
      await _artRepository.update(layer.id, name: name, conditions: conditions);
    } catch (_) {
      // Realtime (or the next open) reconciles; nothing here to shout about.
    }
  }

  Future<void> deleteLayer(String id) async {
    layers = layers.where((l) => l.id != id).toList();
    notifyListeners();
    try {
      await _artRepository.delete(id);
    } catch (_) {
      // Same as above.
    }
  }

  /// Moves [layer] one place up (delta -1) or down (delta 1) within its
  /// slot.
  ///
  /// Rather than swapping two `sort` values — which quietly does nothing
  /// when every layer still sits at the server's default 0 — this renumbers
  /// the whole slot 0..n-1 in the new order and writes back only the rows
  /// whose number actually changed.
  Future<void> moveLayer(ArtLayer layer, int delta) async {
    final ordered = layersIn(layer.slot);
    final index = ordered.indexWhere((l) => l.id == layer.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= ordered.length) return;

    final reordered = [...ordered];
    reordered.insert(target, reordered.removeAt(index));

    final changed = <ArtLayer>[];
    for (var i = 0; i < reordered.length; i++) {
      final original = reordered[i];
      final renumbered = original.copyWith(sort: i.toDouble());
      if (original.sort != renumbered.sort) changed.add(renumbered);
      _replace(renumbered);
    }
    notifyListeners();

    for (final l in changed) {
      try {
        await _artRepository.update(l.id, sort: l.sort);
      } catch (_) {
        // Order is cosmetic-ish (it only breaks ties); a failed write just
        // means the old order comes back on reload.
      }
    }
  }

  void _replace(ArtLayer layer) {
    layers = [
      for (final l in layers)
        if (l.id == layer.id) layer else l,
    ];
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
