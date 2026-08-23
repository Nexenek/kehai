import 'package:flutter/material.dart';

import '../../../domain/models/ping.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

/// The chunky "thinking of you ♡" button that lives on the partner card,
/// under the ambient/distance lines.
///
/// One tap sends the default ([PingKind.thinking]) — that's the entire
/// feature, and anything that made you choose first would spend the thing it
/// exists to save. The other two kinds are one long-press (or one tap on the
/// little ▾) away, which is the right amount of friction for "actually, a
/// hug".
class ThinkingOfYouButton extends StatelessWidget {
  const ThinkingOfYouButton({
    super.key,
    required this.onSend,
    this.canSend = true,
    this.justSent = false,
  });

  /// Fires with the chosen kind. The view model owns the debounce; this
  /// widget only reflects it through [canSend].
  final void Function(PingKind kind) onSend;

  /// False during the debounce window — the button greys out rather than
  /// silently swallowing taps.
  final bool canSend;

  /// True for [pingSentFlourish] after a send: the label flips to "sent ♡"
  /// and the fill goes accent. design-language.md's "one orchestrated
  /// moment" for this card, scaled down to a button.
  final bool justSent;

  Future<void> _pick(BuildContext context) async {
    final kind = await showPingKindPicker(context);
    if (kind != null) onSend(kind);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = canSend && !justSent;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            // Long-press is the discoverable-by-accident route to the other
            // kinds; the ▾ beside it is the discoverable-on-purpose one.
            onLongPress: () => _pick(context),
            child: SizedBox(
              width: double.infinity,
              child: PixelButton(
                key: const Key('ping-send-button'),
                primary: true,
                label: justSent
                    ? AppStrings.pingSentLabel
                    : AppStrings.pingButtonLabel,
                onPressed: enabled
                    ? () => onSend(PingKind.thinking)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _PingKindAffordance(
          onTap: enabled ? () => _pick(context) : null,
        ),
      ],
    );
  }
}

/// The tiny ▾ next to the button — same visual family as the partner card's
/// ✎ doodle affordance.
class _PingKindAffordance extends StatelessWidget {
  const _PingKindAffordance({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppStrings.pingKindTooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: BevelBox(
              key: const Key('ping-kind-affordance'),
              color: colors.chrome,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
              child: Text(
                '▾',
                style: AppTextStyles.button.copyWith(
                  color: colors.ink,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three kinds, as a little window. Returns null if dismissed.
Future<PingKind?> showPingKindPicker(BuildContext context) {
  return showDialog<PingKind>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: RetroWindow(
            title: AppStrings.pingKindPickerTitle,
            onClose: () => Navigator.of(context).pop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final kind in PingKind.values) ...[
                  _PingKindRow(
                    kind: kind,
                    onTap: () => Navigator.of(context).pop(kind),
                  ),
                  if (kind != PingKind.values.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PingKindRow extends StatelessWidget {
  const _PingKindRow({required this.kind, required this.onTap});

  final PingKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: BevelBox(
          key: Key('ping-kind-${kind.id}'),
          color: colors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Text(
                kind.kaomoji,
                style: AppTextStyles.body1.copyWith(color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kind.label,
                  style: AppTextStyles.body2.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mini card's version: a small ♥ in the corner, tap to send the default
/// ping. No kind picker here — the card is 240×150 and a menu on top of it
/// would be bigger than the thing it belongs to.
class MiniPingHeart extends StatefulWidget {
  const MiniPingHeart({
    super.key,
    required this.onSend,
    this.canSend = true,
    this.justSent = false,
    this.legible = false,
  });

  final VoidCallback onSend;
  final bool canSend;
  final bool justSent;

  /// True when the mini card is genuinely transparent, in which case the
  /// heart needs the same legibility halo as the card's text.
  final bool legible;

  @override
  State<MiniPingHeart> createState() => _MiniPingHeartState();
}

class _MiniPingHeartState extends State<MiniPingHeart> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.canSend && !widget.justSent;
    final color = widget.justSent
        ? colors.accent
        : (_hovered && enabled ? colors.accent : colors.chromeAlt);

    return Tooltip(
      message: widget.justSent
          ? AppStrings.pingSentLabel
          : AppStrings.pingMiniTooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          // Opaque so the tap lands here and never falls through to the
          // card's own "expand the window" gesture underneath.
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onSend : null,
          child: Semantics(
            button: true,
            label: AppStrings.pingMiniTooltip,
            // ≥44px of touch target around a 12px glyph, per the a11y floor
            // in design-language.md.
            child: SizedBox(
              width: 24,
              height: 20,
              child: Center(
                child: Text(
                  '♥︎',
                  key: const Key('mini-ping-heart'),
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    height: 1,
                    shadows: widget.legible ? _miniHeartHalo : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Same dark-under-light halo the mini card uses for its own text.
const List<Shadow> _miniHeartHalo = [
  Shadow(color: Color(0xCC000000), blurRadius: 3),
  Shadow(color: Color(0xCCFFFFFF), blurRadius: 6),
];
