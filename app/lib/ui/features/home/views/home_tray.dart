import 'package:flutter/material.dart';

import '../../../../domain/models/pet.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_calendar_glyph.dart';
import '../../../core/widgets/pixel_hourglass.dart';
import '../../../core/widgets/pixel_map_pin.dart';
import '../../pet/pet_painter.dart' show petSpriteFor, petGridSize;
import 'home_layout.dart';

/// The tray sections that open in the drawer. [mood], [pet] and [thumbkiss]
/// sit on the primary bar next to doodle (which is deliberately absent from
/// this enum — its button opens the canvas dialog directly, per
/// kb/platform-desktop.md); everything else lives behind the ✚ "more" grid.
enum TraySection {
  mood,
  pet,
  thumbkiss,
  countdowns,
  calendar,
  notes,
  instants,
  map,
  board,
  question,
  art,
  files,
}

/// Sections that get their own primary tray button. Anything not in here
/// shows up as a grid tile behind ✚ instead (see [_MoreGrid]).
const Set<TraySection> _primarySections = {
  TraySection.mood,
  TraySection.pet,
  TraySection.thumbkiss,
};

/// A glyph drawn in whatever colour reads on its current background.
typedef GlyphBuilder = Widget Function(Color color);

/// One section's glyph + label, as shown wherever that section needs to
/// identify itself outside its own window: a tray button, a ✚ grid tile, or
/// (see `home_layout.dart`'s `HomeColumn`) a collapsed section strip in the
/// phone column. Kept in one table so those places can't drift apart.
class TraySectionArt {
  const TraySectionArt({required this.glyph, required this.label});

  final GlyphBuilder glyph;
  final String label;
}

/// Every home section's glyph + label, keyed by [TraySection]. Built from
/// the same glyph widgets/labels the tray bar and ✚ grid always used —
/// gathered here so nothing else has to redeclare them.
final Map<TraySection, TraySectionArt> traySectionArt = {
  TraySection.mood: TraySectionArt(
    glyph: _textGlyph('♥︎'),
    label: AppStrings.trayMood,
  ),
  TraySection.pet: TraySectionArt(glyph: _petGlyph, label: AppStrings.trayPet),
  TraySection.thumbkiss: TraySectionArt(
    glyph: _thumbKissGlyph,
    label: AppStrings.trayThumbKiss,
  ),
  TraySection.countdowns: TraySectionArt(
    glyph: (color) => PixelHourglass(color: color),
    label: AppStrings.trayCountdowns,
  ),
  TraySection.calendar: TraySectionArt(
    glyph: (color) => PixelCalendarGlyph(color: color),
    label: AppStrings.trayCalendar,
  ),
  TraySection.notes: TraySectionArt(
    glyph: _textGlyph('≡'),
    label: AppStrings.trayNotes,
  ),
  TraySection.instants: TraySectionArt(
    // ◉ (BMP "fisheye") reads as a camera lens and, unlike an emoji camera,
    // can't be hijacked by Android's color-emoji font.
    glyph: _textGlyph('◉'),
    label: AppStrings.trayInstants,
  ),
  TraySection.map: TraySectionArt(
    glyph: (color) => PixelMapPin(color: color),
    label: AppStrings.trayMap,
  ),
  TraySection.board: TraySectionArt(
    glyph: _textGlyph('▦'),
    label: AppStrings.trayBoard,
  ),
  TraySection.question: TraySectionArt(
    glyph: _textGlyph('✉'),
    label: AppStrings.trayQuestion,
  ),
  TraySection.art: TraySectionArt(
    glyph: _textGlyph('✿'),
    label: AppStrings.trayArt,
  ),
  TraySection.files: TraySectionArt(
    glyph: _textGlyph('▤'),
    label: AppStrings.trayFiles,
  ),
};

/// Slide-up timing for the drawer. One short, well-behaved move, per
/// design-language.md's "smooth ≠ busy".
const Duration kDrawerDuration = Duration(milliseconds: 200);

/// What the drawer is currently showing: the ✚ grid itself, or one section's
/// content (reached either straight from a primary button or picked out of
/// the grid).
enum _DrawerContent { grid, section }

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
  /// Whether the drawer is currently slid up. Independent of [_content]/
  /// [_showing] so both stay put (and keep rendering) while it slides back
  /// down — same reasoning as the old single-section version's `_showing`.
  bool _isOpen = false;

  /// The grid, or a specific section's content.
  _DrawerContent _content = _DrawerContent.section;

  /// The last section shown — kept mounted while the drawer slides back
  /// down, so it doesn't blink away mid-animation.
  TraySection _showing = TraySection.mood;

  /// How much of the space under the partner window a drawer may take. Short
  /// of the top so the partner card is never fully covered.
  static const double _drawerHeightFactor = 0.72;

  void _selectPrimary(TraySection section) {
    setState(() {
      if (_isOpen &&
          _content == _DrawerContent.section &&
          _showing == section) {
        _isOpen = false;
      } else {
        _isOpen = true;
        _content = _DrawerContent.section;
        _showing = section;
      }
    });
  }

  /// The ✚ button: opens the grid from closed, steps back to the grid from
  /// any section (the "back/✚ affordance to return to the grid"), and
  /// closes only when the grid itself is already what's showing.
  void _toggleMore() {
    setState(() {
      if (!_isOpen) {
        _isOpen = true;
        _content = _DrawerContent.grid;
      } else if (_content == _DrawerContent.grid) {
        _isOpen = false;
      } else {
        _content = _DrawerContent.grid;
      }
    });
  }

  void _selectFromGrid(TraySection section) {
    setState(() {
      _isOpen = true;
      _content = _DrawerContent.section;
      _showing = section;
    });
  }

  void _close() => setState(() => _isOpen = false);

  bool get _moreActive =>
      _isOpen &&
      (_content == _DrawerContent.grid || !_primarySections.contains(_showing));

  HomeSectionBuilder _builderFor(TraySection section) => switch (section) {
    TraySection.mood => widget.sections.mood,
    TraySection.pet => widget.sections.pet,
    TraySection.thumbkiss => widget.sections.thumbkiss,
    TraySection.countdowns => widget.sections.countdowns,
    TraySection.calendar => widget.sections.calendar,
    TraySection.notes => widget.sections.notes,
    TraySection.instants => widget.sections.instants,
    TraySection.map => widget.sections.map,
    TraySection.board => widget.sections.board,
    TraySection.question => widget.sections.question,
    TraySection.art => widget.sections.art,
    TraySection.files => widget.sections.files,
  };

  Widget _drawerContent(BuildContext context) {
    if (_content == _DrawerContent.grid) {
      return _MoreGrid(onSelect: _selectFromGrid);
    }
    final section = _builderFor(_showing)(context, _close);
    // Anything reached through the grid gets a small way back to it; the
    // primary sections (mood/pet/thumbkiss) never need one — their own tray
    // button already toggles them.
    if (_primarySections.contains(_showing)) return section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _BackToGridButton(
            onTap: () => setState(() => _content = _DrawerContent.grid),
          ),
        ),
        const SizedBox(height: 6),
        section,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      offset: _isOpen ? Offset.zero : const Offset(0, 1),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        key: const Key('home-tray-drawer-guard'),
                        ignoring: !_isOpen,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                constraints.maxHeight * _drawerHeightFactor,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            child: SingleChildScrollView(
                              child: _drawerContent(context),
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
          moodSelected:
              _isOpen &&
              _content == _DrawerContent.section &&
              _showing == TraySection.mood,
          petSelected:
              _isOpen &&
              _content == _DrawerContent.section &&
              _showing == TraySection.pet,
          thumbKissSelected:
              _isOpen &&
              _content == _DrawerContent.section &&
              _showing == TraySection.thumbkiss,
          moreSelected: _moreActive,
          onSelectMood: () => _selectPrimary(TraySection.mood),
          onSelectPet: () => _selectPrimary(TraySection.pet),
          onSelectThumbKiss: () => _selectPrimary(TraySection.thumbkiss),
          onToggleMore: _toggleMore,
          onOpenDoodle: widget.sections.onOpenDoodle,
        ),
      ],
    );
  }
}

/// The bottom bar itself: five chunky pixel buttons, glyph over label —
/// mood, doodle, pet, thumb-kiss, and ✚ more.
class _TrayBar extends StatelessWidget {
  const _TrayBar({
    required this.moodSelected,
    required this.petSelected,
    required this.thumbKissSelected,
    required this.moreSelected,
    required this.onSelectMood,
    required this.onSelectPet,
    required this.onSelectThumbKiss,
    required this.onToggleMore,
    required this.onOpenDoodle,
  });

  final bool moodSelected;
  final bool petSelected;
  final bool thumbKissSelected;
  final bool moreSelected;
  final VoidCallback onSelectMood;
  final VoidCallback onSelectPet;
  final VoidCallback onSelectThumbKiss;
  final VoidCallback onToggleMore;
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
                glyph: traySectionArt[TraySection.mood]!.glyph,
                label: traySectionArt[TraySection.mood]!.label,
                selected: moodSelected,
                onTap: onSelectMood,
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
                buttonKey: const Key('tray-pet'),
                glyph: traySectionArt[TraySection.pet]!.glyph,
                label: traySectionArt[TraySection.pet]!.label,
                selected: petSelected,
                onTap: onSelectPet,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-thumbkiss'),
                glyph: traySectionArt[TraySection.thumbkiss]!.glyph,
                label: traySectionArt[TraySection.thumbkiss]!.label,
                selected: thumbKissSelected,
                onTap: onSelectThumbKiss,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _TrayButton(
                buttonKey: const Key('tray-more'),
                glyph: _textGlyph('✚'),
                label: AppStrings.trayMore,
                selected: moreSelected,
                onTap: onToggleMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sections shown as ✚ grid tiles, in tile order — everything not on
/// the primary bar. Glyph and label for each come out of [traySectionArt];
/// a tile's key is just `tray-grid-<section.name>`.
const List<TraySection> _gridSections = [
  TraySection.countdowns,
  TraySection.calendar,
  TraySection.notes,
  TraySection.instants,
  TraySection.map,
  TraySection.board,
  TraySection.question,
  TraySection.art,
  TraySection.files,
];

/// The grid the ✚ button opens: a labeled pixel button per section that no
/// longer fits the primary bar.
class _MoreGrid extends StatelessWidget {
  const _MoreGrid({required this.onSelect});

  final ValueChanged<TraySection> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      key: const Key('tray-more-grid'),
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1,
      children: [
        for (final section in _gridSections)
          _TrayButton(
            buttonKey: Key('tray-grid-${section.name}'),
            glyph: traySectionArt[section]!.glyph,
            label: traySectionArt[section]!.label,
            selected: false,
            onTap: () => onSelect(section),
          ),
      ],
    );
  }
}

/// The small "back to more" affordance shown above a section that was
/// reached through the ✚ grid (design-language.md "one orchestrated moment
/// per screen" — no animation here, just an honest way back).
class _BackToGridButton extends StatelessWidget {
  const _BackToGridButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppStrings.trayBackToMoreTooltip,
      child: GestureDetector(
        key: const Key('tray-back-to-grid'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: BevelBox(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              '◂ ${AppStrings.trayMore}',
              style: AppTextStyles.caption.copyWith(color: colors.accent),
            ),
          ),
        ),
      ),
    );
  }
}

GlyphBuilder _textGlyph(String glyph) =>
    (color) => Text(
      glyph,
      style: AppTextStyles.caption.copyWith(color: color, height: 1),
    );

/// The shared pet's blob silhouette, at mini scale — a cheap reuse of
/// [petSpriteFor]'s cell grid (just the body cells, one flat colour) rather
/// than the full multi-colour [PetPainter] composite, which is more detail
/// than a 20px tray glyph can show anyway.
Widget _petGlyph(Color color) => SizedBox(
  width: 20,
  height: 20,
  child: CustomPaint(painter: _PetGlyphPainter(color: color)),
);

class _PetGlyphPainter extends CustomPainter {
  const _PetGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sprite = petSpriteFor(PetVariant.blob);
    final cell = size.shortestSide / petGridSize;
    if (cell <= 0) return;
    final paint = Paint()..color = color;
    for (var y = 0; y < petGridSize; y++) {
      for (var x = 0; x < petGridSize; x++) {
        if (!sprite.isBody(x, y)) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PetGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Two small overlapping circles — the thumb-kiss tray glyph
/// (design-language.md's painted-not-emoji rule; the real touch area glows
/// like this too, see `thumb_kiss_painter.dart`).
Widget _thumbKissGlyph(Color color) => SizedBox(
  width: 20,
  height: 14,
  child: CustomPaint(painter: _ThumbKissGlyphPainter(color: color)),
);

class _ThumbKissGlyphPainter extends CustomPainter {
  const _ThumbKissGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    final cy = size.height / 2;
    canvas.drawCircle(Offset(size.width / 2 - r * 0.55, cy), r, paint);
    canvas.drawCircle(Offset(size.width / 2 + r * 0.55, cy), r, paint);
  }

  @override
  bool shouldRepaint(covariant _ThumbKissGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.buttonKey,
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key buttonKey;
  final GlyphBuilder glyph;
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
