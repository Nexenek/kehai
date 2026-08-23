import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models/ambient_line.dart';

/// The paper-doll slots, in paint order (ADR-13: "background → base pose →
/// outfit → expression → prop"). Order here IS the z-order: the enum's
/// declaration order is the order layers are stacked, so the artist never
/// has to reason about depth across slots — only about which slot a drawing
/// belongs in.
enum ArtSlot {
  background,
  base,
  outfit,
  expression,
  prop;

  static ArtSlot? tryParse(String? raw) {
    if (raw == null) return null;
    for (final slot in ArtSlot.values) {
      if (slot.name == raw) return slot;
    }
    return null;
  }
}

/// The ambient dimension a layer can be conditioned on — the same five
/// states the partner card's ambient line already resolves
/// ([resolveAmbientLine]), named for the artist rather than for the
/// telemetry contract.
const List<String> artAmbientKinds = [
  'music',
  'away',
  'phone',
  'computer',
  'activity',
];

/// Maps the already-resolved ambient line onto the art system's vocabulary.
/// Null (nothing known about what they're doing) simply means the ambient
/// dimension doesn't participate in matching — every layer is then judged on
/// mood alone.
String? artAmbientKindFor(AmbientLine? line) {
  if (line == null) return null;
  return switch (line.kind) {
    AmbientLineKind.nowPlaying => 'music',
    AmbientLineKind.activity => 'activity',
    AmbientLineKind.atComputer => 'computer',
    AmbientLineKind.onPhone => 'phone',
    // "probably asleep" is the warm form of away (long idle at their local
    // night) — the same drawing should cover both, so it folds into 'away'
    // rather than becoming a sixth kind the artist has to think about.
    AmbientLineKind.asleep => 'away',
    AmbientLineKind.away => 'away',
  };
}

/// When a layer is allowed to show: the mood ids and ambient kinds it's for,
/// plus whether it's its slot's fallback.
///
/// An EMPTY set means "matches anything in that dimension" — that's the
/// forgiving default, so an artist who uploads a drawing without ticking a
/// single box still sees it appear.
@immutable
class ArtConditions {
  const ArtConditions({
    this.moods = const {},
    this.ambient = const {},
    this.isDefault = false,
  });

  /// Mood ids from `MoodCatalog` (happy, sleepy, …). Empty = any mood.
  final Set<String> moods;

  /// Ambient kinds from [artAmbientKinds]. Empty = any ambient state.
  final Set<String> ambient;

  /// "use me when nothing more specific matches" — the slot's fallback.
  final bool isDefault;

  /// Matches everything, fallback for nothing. Also what any unparseable
  /// `conditions` blob degrades to (see [fromJson]).
  static const any = ArtConditions();

  bool get isUnconditional => moods.isEmpty && ambient.isEmpty;

  /// Parses the server's `conditions` JSON field, defensively.
  ///
  /// This runs on data the artist can type into a future raw editor, that
  /// an older/newer app version may have written, and that PocketBase hands
  /// back as either a decoded `Map` or (depending on the field/SDK path) a
  /// JSON `String`. It must never throw: the partner window falling back to
  /// a kaomoji is a bad day, an exception in the portrait is a broken app.
  /// Anything it can't make sense of becomes [any].
  factory ArtConditions.fromJson(Object? raw) {
    Object? value = raw;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return any;
      try {
        value = jsonDecode(trimmed);
      } catch (_) {
        return any;
      }
    }
    if (value is! Map) return any;

    return ArtConditions(
      moods: _stringSet(value['moods']),
      ambient: _stringSet(value['ambient']),
      isDefault: _bool(value['default']),
    );
  }

  Map<String, dynamic> toJson() => {
    'moods': moods.toList()..sort(),
    'ambient': ambient.toList()..sort(),
    'default': isDefault,
  };

  ArtConditions copyWith({
    Set<String>? moods,
    Set<String>? ambient,
    bool? isDefault,
  }) => ArtConditions(
    moods: moods ?? this.moods,
    ambient: ambient ?? this.ambient,
    isDefault: isDefault ?? this.isDefault,
  );

  /// Tolerates a list of strings (the normal case), a bare string (someone
  /// wrote `"moods": "sleepy"`), and junk elements mixed into a good list.
  static Set<String> _stringSet(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const {} : {trimmed};
    }
    if (value is! Iterable) return const {};
    final out = <String>{};
    for (final item in value) {
      if (item is! String) continue;
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) out.add(trimmed);
    }
    return out;
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is ArtConditions &&
      other.isDefault == isDefault &&
      setEquals(other.moods, moods) &&
      setEquals(other.ambient, ambient);

  @override
  int get hashCode => Object.hash(
    isDefault,
    Object.hashAllUnordered(moods),
    Object.hashAllUnordered(ambient),
  );

  @override
  String toString() =>
      'ArtConditions(moods: $moods, ambient: $ambient, default: $isDefault)';
}

/// One drawn PNG in one slot — an `art_layers` record.
@immutable
class ArtLayer {
  const ArtLayer({
    required this.id,
    required this.coupleId,
    required this.slot,
    required this.imageUrl,
    this.name = '',
    this.sort = 0,
    this.conditions = ArtConditions.any,
  });

  final String id;
  final String coupleId;
  final ArtSlot slot;

  /// The artist's own label ("sleepy eyes", "big hoodie") — never shown in
  /// the partner window, only in the manager.
  final String name;
  final String imageUrl;

  /// Order within the slot. Doubles as the tie-break when two layers in one
  /// slot match the current state equally well: lower wins, which is
  /// "higher up the list" in the manager.
  final double sort;

  final ArtConditions conditions;

  ArtLayer copyWith({String? name, double? sort, ArtConditions? conditions}) =>
      ArtLayer(
        id: id,
        coupleId: coupleId,
        slot: slot,
        imageUrl: imageUrl,
        name: name ?? this.name,
        sort: sort ?? this.sort,
        conditions: conditions ?? this.conditions,
      );

  @override
  bool operator ==(Object other) =>
      other is ArtLayer &&
      other.id == id &&
      other.coupleId == coupleId &&
      other.slot == slot &&
      other.name == name &&
      other.imageUrl == imageUrl &&
      other.sort == sort &&
      other.conditions == conditions;

  @override
  int get hashCode =>
      Object.hash(id, coupleId, slot, name, imageUrl, sort, conditions);

  @override
  String toString() => 'ArtLayer(${slot.name}, "$name", sort: $sort)';
}

/// How well a layer fits the partner's current state. Higher wins; null
/// means the layer is ruled out entirely.
///
/// The ladder is the one the brief locks in — mood+ambient > mood > ambient
/// > default > none — with one addition at the bottom: a layer that names no
/// conditions at all and isn't flagged default still scores [artMatchNone]
/// rather than being rejected. That's the "just upload a drawing and it
/// shows up" path, and it's the difference between the art system working
/// on the artist's first try and silently rendering nothing.
///
/// A layer is RULED OUT when it names a dimension the current state
/// contradicts: a layer for `moods: [sleepy]` never appears while they're
/// happy, even if it's marked as the slot's default. "Default" is a
/// tie-break among layers that already fit, not an override.
const int artMatchNone = 0;
const int artMatchDefault = 1;
const int artMatchAmbient = 2;
const int artMatchMood = 3;
const int artMatchMoodAndAmbient = 4;

int? artLayerMatchScore(ArtLayer layer, {String? moodId, String? ambientKind}) {
  final conditions = layer.conditions;

  final wantsMood = conditions.moods.isNotEmpty;
  final moodMatches =
      wantsMood && moodId != null && conditions.moods.contains(moodId);
  if (wantsMood && !moodMatches) return null;

  final wantsAmbient = conditions.ambient.isNotEmpty;
  final ambientMatches =
      wantsAmbient &&
      ambientKind != null &&
      conditions.ambient.contains(ambientKind);
  if (wantsAmbient && !ambientMatches) return null;

  if (moodMatches && ambientMatches) return artMatchMoodAndAmbient;
  if (moodMatches) return artMatchMood;
  if (ambientMatches) return artMatchAmbient;
  return conditions.isDefault ? artMatchDefault : artMatchNone;
}

/// Picks the single layer to draw for [slot], or null if nothing fits.
///
/// Ties (two equally specific layers) are broken by [ArtLayer.sort] ascending
/// and then by id, so the same state always composites the same scene —
/// a partner window that flickered between two outfits on every rebuild
/// would be worse than no art at all.
ArtLayer? pickArtLayerForSlot(
  List<ArtLayer> layers,
  ArtSlot slot, {
  String? moodId,
  String? ambientKind,
}) {
  ArtLayer? best;
  int bestScore = -1;

  for (final layer in layers) {
    if (layer.slot != slot) continue;
    final score = artLayerMatchScore(
      layer,
      moodId: moodId,
      ambientKind: ambientKind,
    );
    if (score == null) continue;

    if (best == null || score > bestScore) {
      best = layer;
      bestScore = score;
      continue;
    }
    if (score == bestScore && _breaksTie(layer, best)) {
      best = layer;
    }
  }
  return best;
}

bool _breaksTie(ArtLayer candidate, ArtLayer current) {
  if (candidate.sort != current.sort) return candidate.sort < current.sort;
  return candidate.id.compareTo(current.id) < 0;
}

/// Composites the partner's status scene: one layer per slot, in paint
/// order, ready to be stacked into a fixed square canvas.
///
/// Returns an EMPTY list when there's no scene to show — which happens when
/// the couple has no art yet, or when nothing in the `base` slot fits the
/// partner's current state. A scene without a base pose is a floating
/// hoodie and a pair of eyes, so "no base" means "no scene": the caller
/// falls back to the mood kaomoji, which is always honest.
List<ArtLayer> resolveArtScene(
  List<ArtLayer> layers, {
  String? moodId,
  String? ambientKind,
}) {
  if (layers.isEmpty) return const [];

  final scene = <ArtLayer>[];
  var hasBase = false;
  for (final slot in ArtSlot.values) {
    final picked = pickArtLayerForSlot(
      layers,
      slot,
      moodId: moodId,
      ambientKind: ambientKind,
    );
    if (picked == null) continue;
    if (slot == ArtSlot.base) hasBase = true;
    scene.add(picked);
  }
  return hasBase ? scene : const [];
}

/// The manager's ordering for one slot's list: [ArtLayer.sort] ascending,
/// ties by id so the list never reshuffles under the artist between builds.
List<ArtLayer> artLayersInSlot(List<ArtLayer> layers, ArtSlot slot) {
  final inSlot = layers.where((l) => l.slot == slot).toList()
    ..sort((a, b) {
      final bySort = a.sort.compareTo(b.sort);
      return bySort != 0 ? bySort : a.id.compareTo(b.id);
    });
  return inSlot;
}
