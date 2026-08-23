import '../../../domain/art_scene.dart';
import '../../core/strings/app_strings.dart';

/// The artist's words for each slot. Kept out of [ArtSlot] itself so the
/// domain layer stays free of UI copy (same split as `NoteColor` vs. its
/// labels) — and so the eventual Polish l10n only has to touch AppStrings.
String artSlotLabel(ArtSlot slot) => switch (slot) {
  ArtSlot.background => AppStrings.artSlotBackground,
  ArtSlot.base => AppStrings.artSlotBase,
  ArtSlot.outfit => AppStrings.artSlotOutfit,
  ArtSlot.expression => AppStrings.artSlotExpression,
  ArtSlot.prop => AppStrings.artSlotProp,
};

String artSlotHint(ArtSlot slot) => switch (slot) {
  ArtSlot.background => AppStrings.artSlotBackgroundHint,
  ArtSlot.base => AppStrings.artSlotBaseHint,
  ArtSlot.outfit => AppStrings.artSlotOutfitHint,
  ArtSlot.expression => AppStrings.artSlotExpressionHint,
  ArtSlot.prop => AppStrings.artSlotPropHint,
};
