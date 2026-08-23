import 'package:flutter/material.dart';

import '../../../../data/services/desktop_window_service.dart';
import '../../../../domain/models/ambient_line.dart';
import '../../../../domain/models/mood.dart';
import '../../../../domain/models/partner_status.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/marquee_text.dart';
import 'device_indicator.dart';

/// The little always-there window: the whole app, shrunk to a glanceable
/// card (kb/platform-desktop.md's mini state).
///
/// It shows exactly what you'd want from the corner of your eye — how
/// they're feeling, what they're up to, whether they're around — and nothing
/// else. Click it to open the panel; drag it anywhere.
class MiniPartnerWindow extends StatefulWidget {
  const MiniPartnerWindow({
    super.key,
    required this.partnerName,
    required this.status,
    required this.phoneOnline,
    required this.desktopOnline,
    this.ambientLine,
    this.onExpand,
    this.onDragStart,
    this.transparentCorners = false,
  });

  final String partnerName;
  final PartnerStatus? status;
  final bool phoneOnline;
  final bool desktopOnline;
  final AmbientLine? ambientLine;

  /// Clicking the card opens the full panel.
  final VoidCallback? onExpand;

  /// Dragging it moves the OS window (the card has no title bar of its own).
  final VoidCallback? onDragStart;

  /// True when the window behind us is actually transparent, in which case
  /// the corner notches read as pixel-stepped corners. Where transparency
  /// isn't available they'd just show the window's own background, so we
  /// leave the card square instead.
  final bool transparentCorners;

  @override
  State<MiniPartnerWindow> createState() => _MiniPartnerWindowState();
}

class _MiniPartnerWindowState extends State<MiniPartnerWindow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = widget.status != null
        ? MoodCatalog.byId(widget.status!.moodId)
        : null;
    final line = widget.ambientLine;
    final transparent = widget.transparentCorners;

    TextStyle legible(TextStyle style) =>
        transparent ? style.copyWith(shadows: _legibilityHalo) : style;

    final card = Container(
      decoration: BoxDecoration(
        // A genuinely see-through window shows the desktop straight
        // through, so the fill drops out entirely — only the ink border
        // (and the pixel-stepped clip below) draw the card's silhouette.
        // Where we're not transparent, the pastel fill is what makes this
        // read as a card at all.
        color: transparent ? null : colors.surface,
        border: Border.all(
          color: _hovered ? colors.accent : colors.ink,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.partnerName.isEmpty
                      ? AppStrings.partnerCardTitleFallback
                      : widget.partnerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: legible(
                    AppTextStyles.caption.copyWith(color: colors.chromeAlt),
                  ),
                ),
              ),
              DeviceIndicator(
                phoneOnline: widget.phoneOnline,
                desktopOnline: widget.desktopOnline,
              ),
            ],
          ),
          Expanded(child: PartnerPortrait(mood: mood, legible: transparent)),
          SizedBox(
            height: 18,
            child: line != null
                ? MarqueeText(
                    text: line.text,
                    style: legible(
                      AppTextStyles.caption.copyWith(
                        color: line.kind == AmbientLineKind.nowPlaying
                            ? colors.accent2
                            : colors.ink,
                        fontStyle: line.kind == AmbientLineKind.away
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  )
                : Text(
                    mood?.label ?? AppStrings.miniNobodyYet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: legible(
                      AppTextStyles.caption.copyWith(color: colors.chromeAlt),
                    ),
                  ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: AppStrings.miniExpandTooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onExpand,
          onPanStart: (_) => widget.onDragStart?.call(),
          child: Semantics(
            button: true,
            label: AppStrings.miniExpandTooltip,
            child: Stack(
              children: [
                Positioned.fill(
                  child: widget.transparentCorners
                      ? ClipPath(
                          clipper: const _PixelCornerClipper(),
                          child: card,
                        )
                      : card,
                ),
                // The click affordance: a corner arrow that lights up under
                // the pointer rather than a button competing with the art.
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: Text(
                    '⤢',
                    style: AppTextStyles.caption.copyWith(
                      color: _hovered ? colors.accent : colors.chrome,
                      height: 1,
                    ),
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

/// Knocks a 2px step out of each corner, so the card reads as a rounded
/// *pixel* shape rather than a chamfered vector one. Only used where the
/// window behind is genuinely transparent — otherwise the steps would just
/// expose the window's own background colour.
class _PixelCornerClipper extends CustomClipper<Path> {
  const _PixelCornerClipper();

  /// One pixel step, at the 2px scale the rest of our chrome uses.
  static const double step = 2;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(step, 0)
      ..lineTo(w - step, 0)
      ..lineTo(w - step, step)
      ..lineTo(w, step)
      ..lineTo(w, h - step)
      ..lineTo(w - step, h - step)
      ..lineTo(w - step, h)
      ..lineTo(step, h)
      ..lineTo(step, h - step)
      ..lineTo(0, h - step)
      ..lineTo(0, step)
      ..lineTo(step, step)
      ..close();
  }

  @override
  bool shouldReclip(_PixelCornerClipper oldClipper) => false;
}

/// A soft dark-under-light halo so the mini card's text and kaomoji stay
/// readable when they're sitting directly on an arbitrary desktop
/// background (transparent mode) rather than our own pastel fill: the dark
/// layer keeps it legible over bright wallpaper, the light layer keeps it
/// legible over dark wallpaper, and stacked with no offset neither reads as
/// a directional drop shadow.
const List<Shadow> _legibilityHalo = [
  Shadow(color: Color(0xCC000000), blurRadius: 3),
  Shadow(color: Color(0xCCFFFFFF), blurRadius: 6),
];

/// The partner, as art.
///
/// Today that's their mood kaomoji at display size. This widget exists as
/// its own thing — with its own fixed, centred slot — so the paper-doll
/// character sprite from design-language.md's "signature element" can take
/// over later without the card around it moving a pixel: swap the [Text] for
/// an [Image]/sprite-sheet frame and nothing else changes.
class PartnerPortrait extends StatelessWidget {
  const PartnerPortrait({super.key, required this.mood, this.legible = false});

  final Mood? mood;

  /// True when this portrait may be sitting directly over an unknown
  /// desktop background (the mini card is transparent) rather than our own
  /// surface colour — see [_legibilityHalo].
  final bool legible;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    var style = AppTextStyles.kaomojiLarge.copyWith(
      color: mood?.colorOf(colors) ?? colors.ink,
    );
    if (legible) style = style.copyWith(shadows: _legibilityHalo);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(mood?.kaomoji ?? '(. .)', maxLines: 1, style: style),
      ),
    );
  }
}

/// Wires [MiniPartnerWindow] to the real window: tap expands, drag moves.
class MiniWindowHost extends StatelessWidget {
  const MiniWindowHost({
    super.key,
    required this.partnerName,
    required this.status,
    required this.phoneOnline,
    required this.desktopOnline,
    this.ambientLine,
  });

  final String partnerName;
  final PartnerStatus? status;
  final bool phoneOnline;
  final bool desktopOnline;
  final AmbientLine? ambientLine;

  @override
  Widget build(BuildContext context) {
    final service = DesktopWindowService.instance;
    // A second listenable on top of the home screen's ListenableBuilder on
    // windowMode: mode flips to mini synchronously, but whether the window
    // actually went see-through is a runner round-trip that lands slightly
    // later — this is what repaints the card once that answer is in.
    return ValueListenableBuilder<bool>(
      valueListenable: service.wantsTransparentMini,
      builder: (context, transparent, _) => MiniPartnerWindow(
        partnerName: partnerName,
        status: status,
        phoneOnline: phoneOnline,
        desktopOnline: desktopOnline,
        ambientLine: ambientLine,
        transparentCorners: transparent,
        onExpand: service.windowMode.expand,
        onDragStart: service.startDragging,
      ),
    );
  }
}
