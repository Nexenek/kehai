import 'package:flutter/material.dart';

import '../../../../data/services/prefs_service.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import 'home_tray.dart';

/// Above this width/height ratio the window is wide enough to spread our
/// desktop out side by side; at or below it we stay a tall companion pane.
/// Locked in kb/platform-desktop.md ("if the window is stretched wide
/// (aspect > ~1.2, e.g. maximized 16:9) … the 'our desktop' spread").
const double kSpreadAspectThreshold = 1.2;

/// The three shapes the home screen takes.
///
/// - [column]: the original single scrolling column. What Android and any
///   non-desktop surface always gets — unchanged.
/// - [companion]: the compact desktop pane — partner window pinned up top,
///   pixel tray at the bottom, sections sliding up as a drawer.
/// - [spread]: "our desktop" — partner column left, section windows right.
enum HomeLayoutMode { column, companion, spread }

/// Layout decisions come from the space we actually have, not from the
/// device (flutter-build-responsive-layout: "Flutter apps run in resizable
/// windows … base all layout decisions strictly on available window space").
/// [desktop] only decides whether the desktop shapes are on the table at
/// all — a 9:16 phone and a 9:16 companion pane have the same aspect.
HomeLayoutMode resolveHomeLayoutMode({
  required Size size,
  required bool desktop,
}) {
  if (!desktop) return HomeLayoutMode.column;
  if (size.height <= 0 || !size.height.isFinite || !size.width.isFinite) {
    return HomeLayoutMode.companion;
  }
  return size.width / size.height > kSpreadAspectThreshold
      ? HomeLayoutMode.spread
      : HomeLayoutMode.companion;
}

/// A section of the home screen, built on demand. [onClose] is non-null only
/// where the section is presented as something dismissable (the companion
/// drawer), and gets wired to that window's ♥.
typedef HomeSectionBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onClose,
);

/// Everything the home screen is made of, handed to whichever layout is in
/// play. Keeping these as builders (rather than built widgets) means a
/// drawer only pays for the section it's showing, and the layouts stay pure
/// composition — no view models reach in here.
class HomeSections {
  const HomeSections({
    required this.partner,
    required this.mood,
    required this.pet,
    required this.thumbkiss,
    required this.countdowns,
    required this.calendar,
    required this.notes,
    required this.map,
    required this.instants,
    required this.board,
    required this.question,
    required this.art,
    required this.files,
    required this.onOpenDoodle,
    required this.onLogOut,
    this.extras = const <Widget>[],
  });

  /// The partner window (or the waiting-for-partner window) — the one thing
  /// that is always on screen, in every layout.
  final Widget partner;

  final HomeSectionBuilder mood;

  /// The shared pet (kb/features.md "Shared pet").
  final HomeSectionBuilder pet;

  /// Thumb-kiss — the live touch area (kb/features.md "Thumb-kiss").
  final HomeSectionBuilder thumbkiss;

  final HomeSectionBuilder countdowns;

  /// The shared calendar (kb/decisions.md ADR-7's v1 deviation: a
  /// kehai-native `calendar_events` collection instead of CalDAV — see
  /// server/migrations/11_calendar.go).
  final HomeSectionBuilder calendar;

  final HomeSectionBuilder notes;

  /// "where we are" — the map, distance-apart line and my ghost switch
  /// (kb/contracts.md "Location").
  final HomeSectionBuilder map;

  /// Instants — the shared quick-photo feed (kb/contracts.md "Instants").
  final HomeSectionBuilder instants;

  /// The shared decorable board (kb/features.md "Shared board").
  final HomeSectionBuilder board;

  /// The daily question, blind reveal (kb/features.md "Daily question").
  final HomeSectionBuilder question;

  /// "our art ✎" — the paper-doll layer manager (kb ADR-13).
  final HomeSectionBuilder art;

  /// The shared file shelf (kb/features.md "Shared file storage").
  final HomeSectionBuilder files;

  /// Doodles have no drawer: the tray's ✎ opens the canvas dialog directly.
  final VoidCallback onOpenDoodle;

  /// Only the phone column shows a log-out button of its own; on desktop it
  /// lives in the window title bar with the rest of the chrome.
  final VoidCallback onLogOut;

  /// Platform extras that only belong in the phone column (the "phone
  /// superpowers" entry point).
  final List<Widget> extras;
}

/// Picks the layout for the space available and builds it. Split out from
/// `HomeScreen` so the switch can be tested with stub sections instead of a
/// full set of live view models.
class HomeBody extends StatelessWidget {
  const HomeBody({
    super.key,
    required this.sections,
    required this.desktop,
    required this.prefs,
  });

  final HomeSections sections;

  /// Whether desktop layouts apply at all — [DesktopWindowService.isSupported]
  /// in the app, a fixed value in tests.
  final bool desktop;

  /// Only [HomeColumn] uses this (to persist which sections are collapsed) —
  /// threaded through here rather than reached via an inherited widget so
  /// the layouts stay pure composition, same as [sections].
  final PrefsService prefs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = resolveHomeLayoutMode(
          size: constraints.biggest,
          desktop: desktop,
        );
        return switch (mode) {
          HomeLayoutMode.column => HomeColumn(sections: sections, prefs: prefs),
          HomeLayoutMode.companion => CompanionHome(sections: sections),
          HomeLayoutMode.spread => HomeSpread(sections: sections),
        };
      },
    );
  }
}

/// The app-name strip for the phone column. Desktop windows don't use it —
/// [KehaiTitleBar] is already the app's one piece of window chrome there.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.onLogOut});

  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            AppStrings.appName,
            style: AppTextStyles.heading.copyWith(color: colors.ink),
          ),
        ),
        PixelButton(label: AppStrings.logOut, onPressed: onLogOut),
      ],
    );
  }
}

/// One entry in [HomeColumn]'s list of collapsible sections: which
/// [TraySection] it corresponds to (for its glyph/label and its saved
/// collapsed/expanded state) and the builder that produces its content.
typedef _ColumnEntry = ({TraySection section, HomeSectionBuilder builder});

/// Every [HomeColumn] section other than the partner card, in display
/// order. The partner card itself isn't here — it's never collapsible and
/// always renders first, straight from [HomeSections.partner].
List<_ColumnEntry> _columnEntries(HomeSections sections) => [
  (section: TraySection.mood, builder: sections.mood),
  (section: TraySection.pet, builder: sections.pet),
  (section: TraySection.question, builder: sections.question),
  (section: TraySection.thumbkiss, builder: sections.thumbkiss),
  (section: TraySection.countdowns, builder: sections.countdowns),
  (section: TraySection.calendar, builder: sections.calendar),
  (section: TraySection.notes, builder: sections.notes),
  (section: TraySection.instants, builder: sections.instants),
  (section: TraySection.files, builder: sections.files),
  (section: TraySection.board, builder: sections.board),
  (section: TraySection.art, builder: sections.art),
  (section: TraySection.map, builder: sections.map),
];

/// Sections collapsed on first run — everything except mood, the one
/// section worth seeing at a glance every time.
final Set<TraySection> _defaultCollapsedSections = {
  for (final section in TraySection.values)
    if (section != TraySection.mood) section,
};

/// The original phone layout: one centred, scrolling column — now with
/// every section but the partner card and mood collapsible, so thirteen
/// stacked windows don't turn into one long scroll (kb/design-language.md
/// "smooth ≠ busy": a slim strip you open on purpose beats a wall of
/// windows you have to scroll past). Android and portrait windows are the
/// only ones that ever see this.
class HomeColumn extends StatefulWidget {
  const HomeColumn({super.key, required this.sections, required this.prefs});

  final HomeSections sections;

  /// Where the collapsed/expanded state persists across launches.
  final PrefsService prefs;

  @override
  State<HomeColumn> createState() => _HomeColumnState();
}

class _HomeColumnState extends State<HomeColumn> {
  late Set<TraySection> _collapsed;

  @override
  void initState() {
    super.initState();
    final saved = widget.prefs.collapsedHomeSections;
    _collapsed = saved == null
        ? _defaultCollapsedSections.toSet()
        : {for (final name in saved) ?_traySectionNamed(name)};
  }

  TraySection? _traySectionNamed(String name) {
    for (final section in TraySection.values) {
      if (section.name == name) return section;
    }
    return null;
  }

  void _toggle(TraySection section) {
    setState(() {
      if (!_collapsed.remove(section)) _collapsed.add(section);
    });
    widget.prefs.setCollapsedHomeSections([
      for (final section in _collapsed) section.name,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeHeader(onLogOut: widget.sections.onLogOut),
              for (final extra in widget.sections.extras) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: extra),
              ],
              const SizedBox(height: 16),
              widget.sections.partner,
              for (final entry in _columnEntries(widget.sections)) ...[
                const SizedBox(height: 20),
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _collapsed.contains(entry.section)
                      ? _CollapsedSectionStrip(
                          section: entry.section,
                          onTap: () => _toggle(entry.section),
                        )
                      : entry.builder(context, () => _toggle(entry.section)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The collapsed stand-in for a section: a slim title-bar-style strip
/// (design-language.md's window chrome, pared down to one line) showing the
/// section's tray glyph and label with a ▸ to invite opening it. Tapping
/// anywhere on the strip expands the section; its own ♥ close (wired to
/// [HomeSectionBuilder]'s `onClose` when expanded) collapses it again.
class _CollapsedSectionStrip extends StatelessWidget {
  const _CollapsedSectionStrip({required this.section, required this.onTap});

  final TraySection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final art = traySectionArt[section]!;
    return Tooltip(
      message: AppStrings.trayOpenTooltip(art.label),
      child: Semantics(
        button: true,
        label: art.label,
        child: GestureDetector(
          key: Key('home-collapsed-${section.name}'),
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: colors.chrome,
                border: Border.all(color: colors.ink, width: 2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  art.glyph(colors.ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      art.label,
                      style: AppTextStyles.titleBar.copyWith(color: colors.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '▸',
                    style: AppTextStyles.titleBar.copyWith(color: colors.ink),
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

/// "Our desktop": partner window (mood and the pet beneath it) held in a
/// fixed left column, with the other eight sections spread across three
/// scrolling columns beside it. No tray — at this width nothing needs
/// hiding.
class HomeSpread extends StatelessWidget {
  const HomeSpread({super.key, required this.sections});

  /// Matches [PartnerCard]'s natural width, so the signature window sits in
  /// its column without stretching.
  static const double partnerColumnWidth = 380;

  final HomeSections sections;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('home-spread'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: partnerColumnWidth,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sections.partner,
                  const SizedBox(height: 16),
                  sections.mood(context, null),
                  const SizedBox(height: 16),
                  sections.pet(context, null),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sections.countdowns(context, null),
                  const SizedBox(height: 16),
                  sections.calendar(context, null),
                  const SizedBox(height: 16),
                  sections.question(context, null),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sections.notes(context, null),
                  const SizedBox(height: 16),
                  sections.thumbkiss(context, null),
                  const SizedBox(height: 16),
                  sections.board(context, null),
                  const SizedBox(height: 16),
                  sections.art(context, null),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Map and instants share the rightmost column — five columns
          // would cramp the grid, and photos read fine under the map.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sections.map(context, null),
                  const SizedBox(height: 16),
                  sections.instants(context, null),
                  const SizedBox(height: 16),
                  sections.files(context, null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
