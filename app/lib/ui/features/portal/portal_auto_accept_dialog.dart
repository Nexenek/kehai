import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/prefs_service.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

// Toggle-row labels: generic on/off vocabulary, not tied to any one
// feature's phrasing (unlike AppStrings.shareFocusedAppOn/TurnOn, which say
// "sharing"). Kept private per the brief — a real "turn on"/"on ✓" pair
// would be a fine app_strings.dart addition later if another toggle wants
// the same words.
const _autoAcceptOn = 'auto-open ✓';
const _autoAcceptOff = 'turn on';

/// Shows the portal screen's ✧ corner dialog: quiet-hours auto-accept,
/// reached from the curtain the same way sharing settings are reached from
/// the desktop title bar (`showSharingSettingsDialog`) — a small modal
/// [Dialog], not a pushed route.
Future<void> showPortalAutoAcceptDialog(
  BuildContext context, {
  required PrefsService prefs,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _PortalAutoAcceptContent(prefs: prefs),
    ),
  );
}

class _PortalAutoAcceptContent extends StatefulWidget {
  const _PortalAutoAcceptContent({required this.prefs});

  final PrefsService prefs;

  @override
  State<_PortalAutoAcceptContent> createState() =>
      _PortalAutoAcceptContentState();
}

class _PortalAutoAcceptContentState extends State<_PortalAutoAcceptContent> {
  late bool _enabled = widget.prefs.portalAutoAcceptEnabled;
  late int _from = widget.prefs.portalAutoAcceptFromHour;
  late int _to = widget.prefs.portalAutoAcceptToHour;

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    unawaited(widget.prefs.setPortalAutoAcceptEnabled(value));
  }

  void _setFrom(int hour) {
    setState(() => _from = hour);
    unawaited(widget.prefs.setPortalAutoAcceptFromHour(hour));
  }

  void _setTo(int hour) {
    setState(() => _to = hour);
    unawaited(widget.prefs.setPortalAutoAcceptToHour(hour));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
        // Same reasoning as showSharingSettingsDialog's own note: the
        // scroll view has to be the outermost bounded box, or RetroWindow's
        // mainAxisSize.min Column sizes to its content instead of respecting
        // this constraint's max.
        child: SingleChildScrollView(
          child: RetroWindow(
            title: AppStrings.portalAutoAcceptTitle,
            onClose: () => Navigator.of(context).pop(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.portalAutoAcceptBody,
                  style: AppTextStyles.body2.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PixelButton(
                    key: const Key('portal-auto-accept-toggle'),
                    primary: _enabled,
                    label: _enabled ? _autoAcceptOn : _autoAcceptOff,
                    onPressed: () => _setEnabled(!_enabled),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.portalAutoAcceptRange(
                    _formatHour(_from),
                    _formatHour(_to),
                  ),
                  style: AppTextStyles.caption.copyWith(color: colors.accent),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _HourPicker(
                        key: const Key('portal-auto-accept-from'),
                        hour: _from,
                        onChanged: _setFrom,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('–', style: AppTextStyles.body1.copyWith(color: colors.ink)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HourPicker(
                        key: const Key('portal-auto-accept-to'),
                        hour: _to,
                        onChanged: _setTo,
                      ),
                    ),
                  ],
                ),
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
    );
  }
}

String _formatHour(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// A plain hour dropdown (0–23), styled to sit on the pixel chrome without
/// pulling in a whole custom picker widget for one wave.
class _HourPicker extends StatelessWidget {
  const _HourPicker({super.key, required this.hour, required this.onChanged});

  final int hour;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.ink, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: hour,
          isExpanded: true,
          dropdownColor: colors.surface,
          style: AppTextStyles.body2.copyWith(color: colors.ink),
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(value: h, child: Text(_formatHour(h))),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}
