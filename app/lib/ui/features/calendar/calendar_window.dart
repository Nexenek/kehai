import 'package:flutter/material.dart';

import '../../../domain/calendar_math.dart';
import '../../../domain/day_math.dart' show countdownDayLabel, daysUntil;
import '../../../domain/models/calendar_event.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'calendar_view_model.dart';
import 'day_events_dialog.dart';
import 'event_dialog.dart';

/// The "calendar" RetroWindow: month navigation, the pixel month grid
/// (Monday-first, up to 3 event dots per day, today outlined), and the
/// upcoming strip underneath. Mirrors `CountdownsWindow`'s shape — a
/// ListenableBuilder-free window handed a live [CalendarViewModel], plus one
/// add button.
class CalendarWindow extends StatelessWidget {
  const CalendarWindow({super.key, required this.viewModel, this.onClose});

  final CalendarViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  void _openDayList(BuildContext context, DateTime day) {
    viewModel.selectDay(day);
    showDayEventsDialog(context, viewModel: viewModel, day: day).then((_) {
      viewModel.clearSelection();
    });
  }

  void _openAdd(BuildContext context) {
    final day = viewModel.selectedDay ?? DateTime.now();
    showEventDialog(
      context,
      initialDate: DateTime(day.year, day.month, day.day, 9),
      onSave: (draft) => viewModel.addEvent(
        title: draft.title,
        starts: draft.starts,
        ends: draft.ends,
        allDay: draft.allDay,
        notes: draft.notes,
        color: draft.color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return RetroWindow(
          title: AppStrings.calendarTitle,
          onClose: onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MonthHeader(viewModel: viewModel),
              const SizedBox(height: 8),
              _MonthGrid(
                viewModel: viewModel,
                onTapDay: (day) => _openDayList(context, day),
              ),
              const SizedBox(height: 12),
              _UpcomingStrip(events: viewModel.upcoming, now: viewModel.now),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: PixelButton(
                  key: const Key('calendar-add'),
                  primary: true,
                  icon: Icons.favorite,
                  label: AppStrings.calendarAddEvent,
                  onPressed: () => _openAdd(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.viewModel});

  final CalendarViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _NavGlyphButton(
          buttonKey: const Key('calendar-prev-month'),
          glyph: '‹',
          tooltip: AppStrings.calendarPrevMonthTooltip,
          onTap: viewModel.prevMonth,
        ),
        Expanded(
          child: Center(
            child: Text(
              viewModel.visibleMonthLabel,
              style: AppTextStyles.heading.copyWith(fontSize: 15, color: colors.ink),
            ),
          ),
        ),
        _NavGlyphButton(
          buttonKey: const Key('calendar-next-month'),
          glyph: '›',
          tooltip: AppStrings.calendarNextMonthTooltip,
          onTap: viewModel.nextMonth,
        ),
        const SizedBox(width: 6),
        GestureDetector(
          key: const Key('calendar-today'),
          onTap: viewModel.goToToday,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: BevelBox(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                AppStrings.calendarTodayButton,
                style: AppTextStyles.caption.copyWith(color: colors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavGlyphButton extends StatelessWidget {
  const _NavGlyphButton({
    required this.buttonKey,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  final Key buttonKey;
  final String glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: buttonKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            child: BevelBox(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Center(
                child: Text(
                  glyph,
                  style: AppTextStyles.heading.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 7×6 Monday-first grid itself: a weekday header row plus 42 day
/// cells, each showing its day number and up to 3 event dots.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.viewModel, required this.onTapDay});

  final CalendarViewModel viewModel;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final days = viewModel.gridDays;

    return Column(
      key: const Key('calendar-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in AppStrings.calendarWeekdayHeaders)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 0.85,
          children: [
            for (final day in days)
              _DayCell(
                key: Key('calendar-day-${day.year}-${day.month}-${day.day}'),
                day: day,
                inMonth: viewModel.isInVisibleMonth(day),
                today: viewModel.isToday(day),
                selected: viewModel.isSelected(day),
                events: viewModel.eventsForDay(day),
                onTap: () => onTapDay(day),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final bool selected;
  final List<CalendarEvent> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dots = events.take(3).toList();
    final dimmed = !inMonth;

    return Semantics(
      button: true,
      selected: selected,
      label: '${day.day}',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: today
                ? BoxDecoration(border: Border.all(color: colors.accent, width: 2))
                : null,
            child: BevelBox(
              color: selected ? colors.accent2 : colors.surface,
              style: selected ? BevelStyle.sunken : BevelStyle.raised,
              padding: const EdgeInsets.all(3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${day.day}',
                    style: AppTextStyles.caption.copyWith(
                      color: dimmed
                          ? colors.chromeAlt
                          : (selected ? colors.surface : colors.ink),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final e in dots)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            color: e.color.colorOf(colors),
                          ),
                      ],
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

/// The next-3-upcoming compact rows under the grid: "in 3 days · dinner
/// date ♡".
class _UpcomingStrip extends StatelessWidget {
  const _UpcomingStrip({required this.events, required this.now});

  final List<CalendarEvent> events;

  /// The view model's "now" — see [CalendarViewModel.now]'s doc comment on
  /// why this isn't just `DateTime.now()` here.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (events.isEmpty) {
      return Text(
        AppStrings.calendarUpcomingEmpty,
        style: AppTextStyles.body2.copyWith(color: colors.ink),
      );
    }
    return Column(
      key: const Key('calendar-upcoming'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  color: e.color.colorOf(colors),
                ),
                Expanded(
                  child: Text(
                    AppStrings.calendarUpcomingRow(
                      countdownDayLabel(
                        daysUntil(relevantUpcomingDay(e, now), now: now),
                      ),
                      e.title,
                    ),
                    style: AppTextStyles.caption.copyWith(color: colors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
