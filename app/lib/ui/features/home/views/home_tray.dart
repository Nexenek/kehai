import 'package:flutter/material.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_hourglass.dart';
import 'home_layout.dart';

/// The tray sections that open as a drawer. Doodle is deliberately absent —
/// its button opens the canvas dialog instead (kb/platform-desktop.md).
enum TraySection { mood, countdowns, notes }

/// Slide-up timing for the drawer. One short, well-behaved move, per
/// design-language.md's "smooth ≠ busy".
const Duration kDrawerDuration = Duration(milliseconds: 200);

/// The compact desktop companion: partner window pinned at the top, a pixel
/// tray bar anchored at the bottom, and one section drawer at a time sliding
/// up from it.
///
/// The drawer is the only thing that rebuilds when it opens or closes: the
/// partner window above it is a widget handed down from [HomeSections], and
/// the slide itself is an implicit animation, so nothing re-runs per frame.
class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key, required this.sections});

  final HomeSections sections;

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  /// Which drawer is open, if any.
  TraySection? _open;

  /// The last section shown — kept mounted while the drawer slides back
  /// down, so it doesn't blink away mid-animation.
  TraySection _showing = TraySection.mood;

  /// How much of the space under the partner window a drawer may take. Short
  /// of the top so the partner card is never fully covered.
  static const double _drawerHeightFactor = 0.72;

  void _select(TraySection section) {
    setState(() {
      if (_open == section) {
        _open = null;
      } else {
        _open = section;
        _showing = section;
      }
    });
  }

  void _close() => setState(() => _open = null);

  HomeSectionBuilder _builderFor(TraySection section) => switch (section) {
    TraySection.mood => widget.sections.mood,
    TraySection.countdowns => widget.sections.countdowns,
    TraySection.notes => widget.sections.notes,
  };

  @override
  Widget build(BuildContext context) {
    final open = _open != null;
    // Reduced motion: the drawer still opens, it just arrives instantly
    // (design-language.md: "respect reduced-motion OS setting: swap
    // animations for instant states").
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kDrawerDuration;

    return Column(
      key: const Key('home-tray'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: widget.sections.partner,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedSlide(
                      key: const Key('home-tray-drawer'),
                      offset: open ? Offset.zero : const Offset(0, 1),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        key: const Key('home-tray-drawer-guard'),
                        ignoring: !open,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                constraints.maxHeight * _drawerHeightFactor,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            child: SingleChildScrollView(
                              child: _builderFor(_showing)(context, _close),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _TrayBar(
          active: _open,
          onSelect: _select,
          onOpenDoodle: widget.sections.onOpenDoodle,
        ),
      ],
    );
  }
}

/// The bottom bar itself: four chunky pixel buttons, glyph over label.
class _TrayBar extends StatelessWidget {
  const _TrayBar({
    required this.active,
    required this.onSelect,
    required this.onOpenDoodle,
  });

  final TraySection? active;
  final ValueChanged<TraySection> onSelect;
  final VoidCallback onOpenDoodle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(top: BorderSide(color: colors.ink, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-mood'),
                glyph: _textGlyph('♥'),
                label: AppStrings.trayMood,
                selected: active == TraySection.mood,
                onTap: () => onSelect(TraySection.mood),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-doodle'),
                glyph: _textGlyph('✎'),
                label: AppStrings.trayDoodle,
                selected: false,
                onTap: onOpenDoodle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-countdowns'),
                glyph: (color) => PixelHourglass(color: color),
                label: AppStrings.trayCountdowns,
                selected: active == TraySection.countdowns,
                onTap: () => onSelect(TraySection.countdowns),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-notes'),
                glyph: _textGlyph('≡'),
                label: AppStrings.trayNotes,
                selected: active == TraySection.notes,
                onTap: () => onSelect(TraySection.notes),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glyph drawn in whatever colour reads on the button's current fill.
typedef _GlyphBuilder = Widget Function(Color color);

_GlyphBuilder _textGlyph(String glyph) =>
    (color) => Text(
      glyph,
      style: AppTextStyles.caption.copyWith(color: color, height: 1),
    );

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.buttonKey,
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key buttonKey;
  final _GlyphBuilder glyph;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.surface : colors.accent;
    return Tooltip(
      message: selected
          ? AppStrings.trayCloseTooltip
          : AppStrings.trayOpenTooltip(label),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          key: buttonKey,
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ConstrainedBox(
              // Accessibility floor: 44px targets even when the art is tiny.
              constraints: const BoxConstraints(minHeight: 44),
              child: BevelBox(
                color: selected ? colors.accent2 : colors.surface,
                style: selected ? BevelStyle.sunken : BevelStyle.raised,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    glyph(foreground),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: selected ? colors.surface : colors.ink,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
