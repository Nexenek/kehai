import 'package:flutter/foundation.dart';

import '../../ui/core/strings/app_strings.dart';

/// Which little creature the couple picked — three painted variants, no
/// image assets anywhere (they're drawn cell by cell, see
/// `ui/features/pet/pet_painter.dart`).
enum PetVariant {
  blob,
  cat,
  star;

  static PetVariant fromString(String? value) => PetVariant.values.firstWhere(
    (v) => v.name == value,
    orElse: () => PetVariant.blob,
  );

  String get label => switch (this) {
    PetVariant.blob => AppStrings.petVariantBlob,
    PetVariant.cat => AppStrings.petVariantCat,
    PetVariant.star => AppStrings.petVariantStar,
  };
}

/// One optional painted accessory, drawn on top of the body.
enum PetOutfit {
  none,
  bow,
  scarf,
  crown;

  static PetOutfit fromString(String? value) => PetOutfit.values.firstWhere(
    (o) => o.name == value,
    orElse: () => PetOutfit.none,
  );

  String get label => switch (this) {
    PetOutfit.none => AppStrings.petOutfitNone,
    PetOutfit.bow => AppStrings.petOutfitBow,
    PetOutfit.scarf => AppStrings.petOutfitScarf,
    PetOutfit.crown => AppStrings.petOutfitCrown,
  };
}

/// A `pets` record — the one shared pet a couple co-parents
/// (server/migrations/6_pet.go, one row per couple).
///
/// Note what is *not* here: no hunger, no mood, no happiness score. Those
/// are derived from [fedAt]/[petAt] at read time (see
/// `ui/features/pet/pet_state.dart`) so nothing ever ticks down on a server
/// timer and the pet can never end up in a punishing state.
@immutable
class Pet {
  const Pet({
    required this.id,
    required this.coupleId,
    this.name = '',
    this.variant = PetVariant.blob,
    this.outfit = PetOutfit.none,
    this.fedAt,
    this.petAt,
  });

  final String id;
  final String coupleId;

  /// May be empty — the server carries no default, so [displayName] fills
  /// in "kehai-chan" for a freshly adopted pet.
  final String name;
  final PetVariant variant;
  final PetOutfit outfit;

  /// Last snack and last cuddle, from either partner. Null means "never" —
  /// only possible for records written outside the app, since adoption
  /// stamps both.
  final DateTime? fedAt;
  final DateTime? petAt;

  String get displayName =>
      name.trim().isEmpty ? AppStrings.petDefaultName : name;

  Pet copyWith({
    String? name,
    PetVariant? variant,
    PetOutfit? outfit,
    DateTime? fedAt,
    DateTime? petAt,
  }) => Pet(
    id: id,
    coupleId: coupleId,
    name: name ?? this.name,
    variant: variant ?? this.variant,
    outfit: outfit ?? this.outfit,
    fedAt: fedAt ?? this.fedAt,
    petAt: petAt ?? this.petAt,
  );
}
