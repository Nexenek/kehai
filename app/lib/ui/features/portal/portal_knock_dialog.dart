import 'package:flutter/material.dart';

import '../../../data/services/portal/portal_engine.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/pixel_button.dart';

/// The in-app "someone's at the window" prompt, for the one case the OS
/// notification correctly refuses to cover: a knock arriving while the user
/// is actively in the app but NOT on the portal screen. Without this, that
/// knock was completely invisible (found on-device — desktop focused on the
/// home panel, phone knocks, silence).
///
/// The dialog watches the engine and dismisses itself the moment the knock
/// stops being answerable — it timed out, the partner hung up, or another
/// of this user's devices took it — so it can never offer a stale "open the
/// curtain" that would no-op (accept() guards on state anyway; this is
/// about not lying to the person looking at the dialog).
Future<void> showPortalKnockDialog(
  BuildContext context, {
  required PortalCallSurface engine,
  required Future<void> Function() onOpen,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PortalKnockDialog(engine: engine, onOpen: onOpen),
  );
}

class _PortalKnockDialog extends StatefulWidget {
  const _PortalKnockDialog({required this.engine, required this.onOpen});

  final PortalCallSurface engine;
  final Future<void> Function() onOpen;

  @override
  State<_PortalKnockDialog> createState() => _PortalKnockDialogState();
}

class _PortalKnockDialogState extends State<_PortalKnockDialog> {
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    widget.engine.addListener(_onEngineChange);
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineChange);
    super.dispose();
  }

  void _onEngineChange() {
    if (_answered || !mounted) return;
    if (widget.engine.state != PortalState.knocked) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: Border.all(color: colors.ink, width: 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.portalKnockedTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.body1.copyWith(color: colors.ink),
            ),
            const SizedBox(height: 16),
            PixelButton(
              label: AppStrings.portalAccept,
              onPressed: () {
                _answered = true;
                Navigator.of(context).pop();
                // Route first, then accept: by the time the camera goes
                // live the curtain screen is what's on screen.
                widget.onOpen();
              },
            ),
            const SizedBox(height: 8),
            PixelButton(
              label: AppStrings.portalDecline,
              dense: true,
              onPressed: () {
                _answered = true;
                Navigator.of(context).pop();
                widget.engine.decline();
              },
            ),
          ],
        ),
      ),
    );
  }
}
