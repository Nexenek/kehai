import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../data/services/notifications/kehai_notifier.dart';
import '../../../../data/services/notifications/kehai_sound.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/sound_settings_view_model.dart';

/// Opens the "sounds ♪" window.
///
/// Its own small dialog rather than a second section inside the ✧ sharing
/// window, for two reasons: the sharing window is about what *leaves* this
/// device (a privacy surface, with a live "what we'd share right now"
/// preview), while this is about what this device does when something
/// arrives — and Android has no ✧ window at all, so folding sounds into it
/// would have left the phone without a way in. It's reachable from both
/// surfaces instead: the ✧ window on desktop, the superpowers screen on
/// Android.
Future<void> showSoundSettingsDialog(
  BuildContext context, {
  required KehaiNotifier notifier,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SoundSettingsContent(notifier: notifier),
    ),
  );
}

/// The window itself. Public so a widget test can pump it without a dialog
/// route, same shape as the sharing-settings window's content widget.
class SoundSettingsContent extends StatefulWidget {
  const SoundSettingsContent({super.key, required this.notifier});

  final KehaiNotifier notifier;

  @override
  State<SoundSettingsContent> createState() => _SoundSettingsContentState();
}

class _SoundSettingsContentState extends State<SoundSettingsContent> {
  late final SoundSettingsViewModel _viewModel = SoundSettingsViewModel(
    notifier: widget.notifier,
  );

  @override
  void initState() {
    super.initState();
    _viewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: maxHeight),
        // Same "scroll view outside the RetroWindow" shape as the sharing
        // window — a SingleChildScrollView handed to RetroWindow's own
        // mainAxisSize.min Column sizes to its content instead of the
        // incoming max, and overflows on a short screen.
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => RetroWindow(
              title: AppStrings.soundsTitle,
              onClose: () => Navigator.of(context).pop(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.soundsIntro,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 16),
                  for (final kind in KehaiEventKind.values) ...[
                    _SoundRow(
                      kind: kind,
                      selected: _viewModel.soundFor(kind),
                      playing: _viewModel.previewing == kind,
                      onChoose: (sound) => _viewModel.choose(kind, sound),
                    ),
                    const SizedBox(height: 14),
                  ],
                  // Why moods aren't on this list.
                  Text(
                    AppStrings.soundsAmbientNote,
                    key: const Key('sounds-ambient-note'),
                    style: AppTextStyles.caption.copyWith(
                      color: colors.chromeAlt,
                    ),
                  ),
                  if (_viewModel.audible == false) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.soundsNoPlayerNote,
                      key: const Key('sounds-no-player-note'),
                      style: AppTextStyles.caption.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                  if (_isAndroid) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.soundsAndroidPreviewNote,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.chromeAlt,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PixelButton(
                      label: AppStrings.soundsDone,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One event type: its label, then the five choices as chunky little chips.
class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.kind,
    required this.selected,
    required this.playing,
    required this.onChoose,
  });

  final KehaiEventKind kind;
  final KehaiSound selected;
  final bool playing;
  final void Function(KehaiSound sound) onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.soundsEventLabel(kind),
                style: AppTextStyles.body1.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (playing)
              Text(
                '♪',
                key: Key('sound-playing-${kind.id}'),
                style: AppTextStyles.body1.copyWith(color: colors.accent),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final sound in KehaiSound.pickable)
              _SoundChip(
                key: Key('sound-${kind.id}-${sound.id}'),
                sound: sound,
                selected: sound == selected,
                onTap: () => onChoose(sound),
              ),
          ],
        ),
      ],
    );
  }
}

class _SoundChip extends StatelessWidget {
  const _SoundChip({
    super.key,
    required this.sound,
    required this.selected,
    required this.onTap,
  });

  final KehaiSound sound;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: BevelBox(
          color: selected ? colors.accent : colors.chrome,
          style: selected ? BevelStyle.sunken : BevelStyle.raised,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            sound.label,
            style: AppTextStyles.caption.copyWith(
              color: selected ? colors.surface : colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
