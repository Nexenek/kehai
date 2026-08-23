import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/art_scene.dart';
import '../../../domain/models/mood.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'art_image_prep.dart';
import 'art_slot_copy.dart';

/// A file the artist picked, in memory.
class ArtPickedFile {
  const ArtPickedFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// How the add-dialog gets bytes. Injectable so widget tests can drive the
/// whole upload flow without a platform file picker.
typedef ArtFilePicker = Future<ArtPickedFile?> Function();

/// The real picker: the OS gallery on Android, a file dialog on desktop
/// (`image_picker`'s desktop backend is `file_selector`). We can't restrict
/// it to PNG on every platform, so PNG-ness is checked on the bytes
/// afterwards — see [checkArtUpload].
Future<ArtPickedFile?> pickArtFile() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  return ArtPickedFile(bytes: await file.readAsBytes(), name: file.name);
}

/// "add a drawing" — pick a PNG, name it, say when it should show up.
Future<void> showAddArtLayerDialog(
  BuildContext context, {
  required ArtSlot slot,
  required Future<bool> Function({
    required String name,
    required ArtConditions conditions,
    required Uint8List bytes,
    required String filename,
  })
  onAdd,
  ArtFilePicker? pickFile,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _AddArtLayerContent(
        slot: slot,
        onAdd: onAdd,
        pickFile: pickFile ?? pickArtFile,
      ),
    ),
  );
}

/// "this drawing" — rename, re-condition, or delete an existing layer.
Future<void> showEditArtLayerDialog(
  BuildContext context, {
  required ArtLayer layer,
  required Future<void> Function(String name, ArtConditions conditions) onSave,
  required VoidCallback onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _EditArtLayerContent(
        layer: layer,
        onSave: onSave,
        onDelete: onDelete,
      ),
    ),
  );
}

class _AddArtLayerContent extends StatefulWidget {
  const _AddArtLayerContent({
    required this.slot,
    required this.onAdd,
    required this.pickFile,
  });

  final ArtSlot slot;
  final Future<bool> Function({
    required String name,
    required ArtConditions conditions,
    required Uint8List bytes,
    required String filename,
  })
  onAdd;
  final ArtFilePicker pickFile;

  @override
  State<_AddArtLayerContent> createState() => _AddArtLayerContentState();
}

class _AddArtLayerContentState extends State<_AddArtLayerContent> {
  final _nameController = TextEditingController();

  ArtPickedFile? _picked;
  ArtConditions _conditions = ArtConditions.any;
  bool _busy = false;
  String? _error;
  String? _warning;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
      _warning = null;
    });
    ArtPickedFile? file;
    try {
      file = await widget.pickFile();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.artPickFailed;
      });
      return;
    }
    if (!mounted) return;
    if (file == null) {
      setState(() => _busy = false);
      return;
    }

    final problem = checkArtUpload(file.bytes);
    if (problem != null) {
      setState(() {
        _busy = false;
        _picked = null;
        _error = switch (problem) {
          ArtUploadProblem.notPng => AppStrings.artNotPng,
          ArtUploadProblem.tooBig => AppStrings.artTooBig,
          ArtUploadProblem.empty => AppStrings.artEmptyFile,
        };
      });
      return;
    }

    final size = readPngSize(file.bytes);
    setState(() {
      _busy = false;
      _picked = file;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _suggestName(file!.name);
      }
      // Not square is a nudge, never a refusal — it's the artist's call.
      _warning = (size != null && !size.isSquare)
          ? AppStrings.artNotSquareWarning(size.toString())
          : null;
    });
  }

  /// "sleepy-eyes.png" → "sleepy eyes", so the artist rarely has to type.
  static String _suggestName(String filename) {
    var base = filename.split('/').last.split('\\').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return base.length > artLayerNameMaxLength
        ? base.substring(0, artLayerNameMaxLength)
        : base;
  }

  Future<void> _submit() async {
    final picked = _picked;
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.onAdd(
      name: _nameController.text.trim(),
      conditions: _conditions,
      bytes: picked.bytes,
      filename: artUploadFilename(widget.slot.name, picked.name),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = AppStrings.artUploadFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final picked = _picked;

    return RetroWindow(
      title: AppStrings.artAddDialogTitle,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${artSlotLabel(widget.slot)} — ${artSlotHint(widget.slot)}',
              style: AppTextStyles.body2.copyWith(color: colors.ink),
            ),
            const SizedBox(height: 10),
            Center(
              child: BevelBox(
                style: BevelStyle.sunken,
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: picked == null
                      ? Center(
                          child: Text(
                            '✎',
                            style: AppTextStyles.kaomojiLarge.copyWith(
                              color: colors.chromeAlt,
                            ),
                          ),
                        )
                      : Image.memory(
                          picked.bytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: PixelButton(
                key: const Key('art-pick-file'),
                icon: Icons.photo_library_outlined,
                label: picked == null
                    ? AppStrings.artChooseFile
                    : AppStrings.artChangeFile,
                onPressed: _busy ? null : _pick,
              ),
            ),
            if (_warning != null) ...[
              const SizedBox(height: 6),
              Text(
                _warning!,
                style: AppTextStyles.caption.copyWith(color: colors.accent2),
              ),
            ],
            const SizedBox(height: 12),
            _NameField(controller: _nameController, enabled: !_busy),
            const SizedBox(height: 12),
            ArtConditionEditor(
              conditions: _conditions,
              onChanged: (c) => setState(() => _conditions = c),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Spacer(),
                PixelButton(
                  key: const Key('art-add-submit'),
                  primary: true,
                  label: _busy ? AppStrings.artUploading : AppStrings.artSave,
                  onPressed: (_busy || picked == null) ? null : _submit,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('art-dialog-error'),
                style: AppTextStyles.caption.copyWith(color: colors.warn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditArtLayerContent extends StatefulWidget {
  const _EditArtLayerContent({
    required this.layer,
    required this.onSave,
    required this.onDelete,
  });

  final ArtLayer layer;
  final Future<void> Function(String name, ArtConditions conditions) onSave;
  final VoidCallback onDelete;

  @override
  State<_EditArtLayerContent> createState() => _EditArtLayerContentState();
}

class _EditArtLayerContentState extends State<_EditArtLayerContent> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.layer.name,
  );
  late ArtConditions _conditions = widget.layer.conditions;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await widget.onSave(_nameController.text.trim(), _conditions);
    navigator.pop();
  }

  void _delete() {
    widget.onDelete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RetroWindow(
      title: AppStrings.artLayerDialogTitle,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: BevelBox(
                style: BevelStyle.sunken,
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 128,
                  height: 128,
                  child: Image.network(
                    widget.layer.imageUrl,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _NameField(controller: _nameController, enabled: true),
            const SizedBox(height: 12),
            ArtConditionEditor(
              conditions: _conditions,
              onChanged: (c) => setState(() => _conditions = c),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                PixelButton(
                  key: const Key('art-layer-delete'),
                  label: AppStrings.artDelete,
                  onPressed: _delete,
                ),
                const Spacer(),
                PixelButton(
                  key: const Key('art-layer-save'),
                  primary: true,
                  label: AppStrings.artSave,
                  onPressed: _save,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppStrings.artAnyHint,
              style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.artNameLabel,
          style: AppTextStyles.caption.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 4),
        TextField(
          key: const Key('art-name-field'),
          controller: controller,
          enabled: enabled,
          style: AppTextStyles.body1,
          maxLength: artLayerNameMaxLength,
          decoration: const InputDecoration(hintText: AppStrings.artNameHint),
        ),
      ],
    );
  }
}

/// The "when should this show up?" half of both dialogs: mood ticks,
/// ambient ticks, and the slot-fallback toggle.
///
/// Deliberately checkboxes rather than a rule builder — the artist is
/// picking occasions, not writing logic, and an empty set reads (and
/// behaves) as "any time".
class ArtConditionEditor extends StatelessWidget {
  const ArtConditionEditor({
    super.key,
    required this.conditions,
    required this.onChanged,
  });

  final ArtConditions conditions;
  final ValueChanged<ArtConditions> onChanged;

  void _toggleMood(String id) {
    final next = {...conditions.moods};
    if (!next.remove(id)) next.add(id);
    onChanged(conditions.copyWith(moods: next));
  }

  void _toggleAmbient(String kind) {
    final next = {...conditions.ambient};
    if (!next.remove(kind)) next.add(kind);
    onChanged(conditions.copyWith(ambient: next));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.artWhenMoodsLabel,
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
                selected: conditions.moods.contains(mood.id),
                onTap: () => _toggleMood(mood.id),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.artWhenAmbientLabel,
          style: AppTextStyles.caption.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final kind in artAmbientKinds)
              ArtTickChip(
                label: AppStrings.artAmbientLabel(kind),
                selected: conditions.ambient.contains(kind),
                onTap: () => _toggleAmbient(kind),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.artAnyHint,
          style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
        ),
        const SizedBox(height: 10),
        ArtTickChip(
          key: const Key('art-default-toggle'),
          label: AppStrings.artDefaultToggle,
          selected: conditions.isDefault,
          onTap: () =>
              onChanged(conditions.copyWith(isDefault: !conditions.isDefault)),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.artDefaultHint,
          style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
        ),
      ],
    );
  }
}

/// A chunky tickable bevel chip — sunken with a ✓ when on, so the state
/// never rides on colour alone (design-language.md's a11y floor).
class ArtTickChip extends StatelessWidget {
  const ArtTickChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: BevelBox(
            color: selected ? colors.chrome : colors.surface,
            style: selected ? BevelStyle.sunken : BevelStyle.raised,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              selected ? '$label ✓' : label,
              style: AppTextStyles.caption.copyWith(color: colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
