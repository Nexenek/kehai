import 'package:flutter/material.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/sharing_settings_view_model.dart';

/// Shows the desktop "sharing ✧" window: the focused-app opt-ins, reachable
/// from the ✧ glyph in `KehaiTitleBar`. Small and modal on purpose — this is
/// a settings *popup*, not a full screen, so it stays a [Dialog] like
/// `showDoodleCanvasDialog` rather than a pushed route.
Future<void> showSharingSettingsDialog(
  BuildContext context, {
  required bool initialShareFocusedApp,
  required bool initialShareUnknownApps,
  required Future<void> Function(bool value) onSetShareFocusedApp,
  required Future<void> Function(bool value) onSetShareUnknownApps,
  VoidCallback? onOpenSounds,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _SharingSettingsContent(
        initialShareFocusedApp: initialShareFocusedApp,
        initialShareUnknownApps: initialShareUnknownApps,
        onSetShareFocusedApp: onSetShareFocusedApp,
        onSetShareUnknownApps: onSetShareUnknownApps,
        onOpenSounds: onOpenSounds,
      ),
    ),
  );
}

class _SharingSettingsContent extends StatefulWidget {
  const _SharingSettingsContent({
    required this.initialShareFocusedApp,
    required this.initialShareUnknownApps,
    required this.onSetShareFocusedApp,
    required this.onSetShareUnknownApps,
    this.onOpenSounds,
  });

  final bool initialShareFocusedApp;
  final bool initialShareUnknownApps;
  final Future<void> Function(bool value) onSetShareFocusedApp;
  final Future<void> Function(bool value) onSetShareUnknownApps;

  /// Opens the "sounds ♪" window. Null leaves the row out entirely (tests,
  /// and any surface with no notifier to hand it).
  final VoidCallback? onOpenSounds;

  @override
  State<_SharingSettingsContent> createState() =>
      _SharingSettingsContentState();
}

class _SharingSettingsContentState extends State<_SharingSettingsContent> {
  late final SharingSettingsViewModel _viewModel = SharingSettingsViewModel(
    initialShareFocusedApp: widget.initialShareFocusedApp,
    initialShareUnknownApps: widget.initialShareUnknownApps,
    onSetShareFocusedApp: widget.onSetShareFocusedApp,
    onSetShareUnknownApps: widget.onSetShareUnknownApps,
  );

  @override
  void dispose() {
    // Stops the preview's ~3s poll timer — it has no reason to keep
    // running (or holding a MethodChannel/process-spawning probe alive)
    // once this dialog is closed.
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Small pop-up window, but the two toggle rows' body copy is long
    // enough to overflow a short/half-height window (a small laptop
    // display, or a phone in landscape) — scroll rather than clip, same
    // shape as the phone-superpowers screen's own SingleChildScrollView.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
        // The scroll view has to be the OUTERMOST bounded box, not nested
        // inside RetroWindow's own (mainAxisSize.min) Column — a
        // SingleChildScrollView handed to that Column as a bare child sizes
        // to its content's full natural height instead of respecting the
        // incoming max, which is the classic "Column doesn't clip its
        // scrollable child" overflow. Wrapping the whole RetroWindow instead
        // means the scroll view gets a real bounded max straight from this
        // ConstrainedBox, and RetroWindow is free to size to its content
        // exactly like every other caller relies on it doing.
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => RetroWindow(
              title: AppStrings.sharingSettingsTitle,
              onClose: () => Navigator.of(context).pop(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.sharingSettingsIntro,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 16),
                  _ToggleRow(
                    key: const Key('sharing-focused-app-toggle'),
                    title: AppStrings.shareFocusedAppTitle,
                    body: AppStrings.shareFocusedAppBody,
                    value: _viewModel.shareFocusedApp,
                    onChanged: _viewModel.setShareFocusedApp,
                  ),
                  const SizedBox(height: 14),
                  _ToggleRow(
                    key: const Key('sharing-unknown-apps-toggle'),
                    title: AppStrings.shareUnknownAppsTitle,
                    body: AppStrings.shareUnknownAppsBody,
                    value: _viewModel.shareUnknownApps,
                    onChanged: _viewModel.setShareUnknownApps,
                  ),
                  const SizedBox(height: 14),
                  // "What we'd share right now" — refreshed every ~3s by
                  // the view model while this dialog is open, so a silent
                  // failure (Wayland/GNOME with no reader, an unmapped app)
                  // is visible instead of the partner's card just never
                  // saying anything (kb/features.md "Focused-app status").
                  Text(
                    _viewModel.preview,
                    key: const Key('sharing-preview'),
                    style: AppTextStyles.caption.copyWith(
                      color: colors.accent,
                    ),
                  ),
                  if (widget.onOpenSounds != null) ...[
                    const SizedBox(height: 18),
                    // Sounds are about what this device does when something
                    // *arrives*, which is the other half of the same
                    // question this window answers — so it's the natural
                    // doorway, even though the window itself is separate
                    // (see showSoundSettingsDialog's doc comment).
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PixelButton(
                        key: const Key('sharing-open-sounds'),
                        label: AppStrings.soundsOpen,
                        onPressed: widget.onOpenSounds,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PixelButton(
                      label: AppStrings.sharingSettingsDone,
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

/// One preference row: label + body copy, then a chunky on/off
/// [PixelButton] — the same "on ✓ / turn on" vocabulary as the
/// phone-superpowers screen's rows, just without the OS-grant framing since
/// this is a plain preference the app fully owns.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTextStyles.body1.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(body, style: AppTextStyles.caption.copyWith(color: colors.ink)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: PixelButton(
            primary: value,
            label: value
                ? AppStrings.shareFocusedAppOn
                : AppStrings.shareFocusedAppTurnOn,
            onPressed: () => onChanged(!value),
          ),
        ),
      ],
    );
  }
}
