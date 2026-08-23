import 'package:flutter/material.dart';

import '../../../domain/art_scene.dart';
import '../../../domain/models/mood.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import '../../core/widgets/win_glyph_button.dart';
import 'art_layer_dialog.dart';
import 'art_scene_view.dart';
import 'art_slot_copy.dart';
import 'art_view_model.dart';

/// The "our art ✎" RetroWindow: every drawing the couple has, grouped by
/// the slot it paints in, plus a live preview of any mood + ambient combo.
///
/// Self-contained, same as `InstantsWindow`/`BoardWindow` — this batch
/// builds the feature but does NOT wire it into the home tray/layout (a
/// coordinator owns that composition); a caller just needs an
/// [ArtViewModel] wired to real repositories.
///
/// The window is written for the artist half of the couple, who may never
/// have used a layer system: the how-to block at the bottom, the plain-word
/// slot names, and the preview pane are the whole onboarding.
class ArtWindow extends StatelessWidget {
  const ArtWindow({
    super.key,
    required this.viewModel,
    this.onClose,
    this.filePicker,
  });

  final ArtViewModel viewModel;

  /// Makes the window's ♥ functional when shown inside the desktop drawer;
  /// decorative (null) elsewhere.
  final VoidCallback? onClose;

  /// Stubbed in tests; null uses the real gallery/file picker.
  final ArtFilePicker? filePicker;

  void _add(BuildContext context, ArtSlot slot) {
    showAddArtLayerDialog(
      context,
      slot: slot,
      pickFile: filePicker,
      onAdd:
          ({
            required name,
            required conditions,
            required bytes,
            required filename,
          }) => viewModel.addLayer(
            slot: slot,
            name: name,
            conditions: conditions,
            imageBytes: bytes,
            filename: filename,
          ),
    );
  }

  void _edit(BuildContext context, ArtLayer layer) {
    showEditArtLayerDialog(
      context,
      layer: layer,
      onSave: (name, conditions) =>
          viewModel.saveLayer(layer, name: name, conditions: conditions),
      onDelete: () => viewModel.deleteLayer(layer.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;

        return RetroWindow(
          title: AppStrings.artTitle,
          onClose: onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (viewModel.isLoading)
                Text(
                  AppStrings.artLoading,
                  style: AppTextStyles.body2.copyWith(color: colors.ink),
                )
              else ...[
                if (viewModel.layers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      AppStrings.artEmpty,
                      style: AppTextStyles.body2.copyWith(color: colors.ink),
                    ),
                  )
                else if (!viewModel.hasBaseLayer)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      AppStrings.artBaseMissing,
                      key: const Key('art-base-missing'),
                      style: AppTextStyles.body2.copyWith(color: colors.accent),
                    ),
                  ),
                _PreviewPane(viewModel: viewModel),
                const SizedBox(height: 14),
                for (final slot in ArtSlot.values) ...[
                  _SlotSection(
                    slot: slot,
                    layers: viewModel.layersIn(slot),
                    onAdd: () => _add(context, slot),
                    onEdit: (layer) => _edit(context, layer),
                    onMove: viewModel.moveLayer,
                  ),
                  const SizedBox(height: 12),
                ],
                const _HowTo(),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The artist's feedback loop: pick a mood and an ambient state, see exactly
/// what their partner's window would show. Without this the only way to
/// check a condition is to wait for the partner to actually feel that way.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.viewModel});

  final ArtViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scene = viewModel.previewScene;

    return BevelBox(
      style: BevelStyle.sunken,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.artPreviewTitle,
            style: AppTextStyles.titleBar.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 8),
          Center(
            child: BevelBox(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: 160,
                height: 160,
                child: scene.isEmpty
                    ? Center(
                        child: Text(
                          MoodCatalog.byId(viewModel.previewMoodId).kaomoji,
                          key: const Key('art-preview-fallback'),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.kaomojiMedium.copyWith(
                            color: colors.chromeAlt,
                          ),
                        ),
                      )
                    : ArtSceneView(scene: scene),
              ),
            ),
          ),
          if (scene.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              AppStrings.artPreviewNoScene,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            AppStrings.artPreviewMoodLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mood in MoodCatalog.all)
                ArtTickChip(
                  label: mood.label,
                  selected: mood.id == viewModel.previewMoodId,
                  onTap: () => viewModel.setPreviewMood(mood.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.artPreviewAmbientLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ArtTickChip(
                label: AppStrings.artPreviewAmbientAny,
                selected: viewModel.previewAmbientKind == null,
                onTap: () => viewModel.setPreviewAmbient(null),
              ),
              for (final kind in artAmbientKinds)
                ArtTickChip(
                  label: AppStrings.artAmbientLabel(kind),
                  selected: viewModel.previewAmbientKind == kind,
                  onTap: () => viewModel.setPreviewAmbient(kind),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One slot: its plain-word name, what belongs in it, its drawings as
/// thumbnails (in pick order, top first), and an "add a drawing" button.
class _SlotSection extends StatelessWidget {
  const _SlotSection({
    required this.slot,
    required this.layers,
    required this.onAdd,
    required this.onEdit,
    required this.onMove,
  });

  final ArtSlot slot;
  final List<ArtLayer> layers;
  final VoidCallback onAdd;
  final ValueChanged<ArtLayer> onEdit;
  final void Function(ArtLayer layer, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${slot.index + 1}. ${artSlotLabel(slot)}',
                style: AppTextStyles.titleBar.copyWith(color: colors.ink),
              ),
            ),
            PixelButton(
              key: Key('art-add-${slot.name}'),
              dense: true,
              label: AppStrings.artAddLayer,
              onPressed: onAdd,
            ),
          ],
        ),
        Text(
          artSlotHint(slot),
          style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
        ),
        const SizedBox(height: 6),
        if (layers.isEmpty)
          Text(
            AppStrings.artSlotEmpty,
            key: Key('art-empty-${slot.name}'),
            style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
          )
        else
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < layers.length; i++) ...[
                _LayerRow(
                  layer: layers[i],
                  canMoveUp: i > 0,
                  canMoveDown: i < layers.length - 1,
                  onEdit: () => onEdit(layers[i]),
                  onMove: (delta) => onMove(layers[i], delta),
                ),
                if (i < layers.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
      ],
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.layer,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onMove,
  });

  final ArtLayer layer;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BevelBox(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          BevelBox(
            style: BevelStyle.sunken,
            padding: const EdgeInsets.all(2),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Image.network(
                layer.imageUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, error, stack) =>
                    ColoredBox(color: colors.chromeAlt),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  layer.name.isEmpty ? artSlotLabel(layer.slot) : layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body2.copyWith(color: colors.ink),
                ),
                Text(
                  _conditionSummary(layer.conditions),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.chromeAlt,
                  ),
                ),
              ],
            ),
          ),
          WinGlyphButton(
            glyph: '▲',
            tooltip: AppStrings.artMoveUpTooltip,
            onTap: canMoveUp ? () => onMove(-1) : null,
          ),
          const SizedBox(width: 4),
          WinGlyphButton(
            glyph: '▼',
            tooltip: AppStrings.artMoveDownTooltip,
            onTap: canMoveDown ? () => onMove(1) : null,
          ),
          const SizedBox(width: 4),
          WinGlyphButton(
            glyph: '✎',
            tooltip: AppStrings.artEditTooltip,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }

  /// One line saying when this drawing shows up, in the artist's words.
  static String _conditionSummary(ArtConditions conditions) {
    final parts = <String>[];
    if (conditions.moods.isNotEmpty) {
      parts.add((conditions.moods.toList()..sort()).join(', '));
    }
    if (conditions.ambient.isNotEmpty) {
      parts.add(
        (conditions.ambient.map(AppStrings.artAmbientLabel).toList()..sort())
            .join(', '),
      );
    }
    if (parts.isEmpty) {
      return conditions.isDefault
          ? '${AppStrings.artAnyHint} · ${AppStrings.artDefaultToggle}'
          : AppStrings.artAnyHint;
    }
    final summary = parts.join(' · ');
    return conditions.isDefault
        ? '$summary · ${AppStrings.artDefaultToggle}'
        : summary;
  }
}

/// The explainer. Long on purpose: it's the whole manual for the person
/// doing the drawing, and it lives where they'll be looking.
class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BevelBox(
      style: BevelStyle.sunken,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.artHowToTitle,
            style: AppTextStyles.titleBar.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.artHowToBody,
            style: AppTextStyles.body2.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }
}
