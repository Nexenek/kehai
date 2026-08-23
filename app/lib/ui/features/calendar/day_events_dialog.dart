import 'package:flutter/material.dart';

import '../../../domain/calendar_math.dart';
import '../../../domain/day_math.dart' show friendlyDate;
import '../../../domain/models/calendar_event.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'calendar_view_model.dart';
import 'event_dialog.dart';

/// Shows [day]'s event list — tapping a day cell in the grid opens this.
/// Stays live-updating while open (wrapped in a [ListenableBuilder] over
/// [viewModel]) so add/edit/delete reflect immediately without having to
/// close and reopen it.
Future<void> showDayEventsDialog(
  BuildContext context, {
  required CalendarViewModel viewModel,
  required DateTime day,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _DayEventsDialogContent(viewModel: viewModel, day: day),
    ),
  );
}

class _DayEventsDialogContent extends StatelessWidget {
  const _DayEventsDialogContent({required this.viewModel, required this.day});

  final CalendarViewModel viewModel;
  final DateTime day;

  void _openNew(BuildContext context) {
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

  void _openEdit(BuildContext context, CalendarEvent event) {
    showEventDialog(
      context,
      existing: event,
      onSave: (draft) => viewModel.updateEvent(
        event.id,
        title: draft.title,
        starts: draft.starts,
        ends: draft.ends,
        allDay: draft.allDay,
        notes: draft.notes,
        color: draft.color,
      ),
      onDelete: () => viewModel.deleteEvent(event.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final events = viewModel.eventsForDay(day);

        return RetroWindow(
          title: friendlyDate(day),
          onClose: () => Navigator.of(context).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    AppStrings.calendarDayEmpty,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                )
              else
                ...events.map(
                  (e) => _DayEventRow(
                    key: Key('day-event-${e.id}'),
                    event: e,
                    onTap: () => _openEdit(context, e),
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: PixelButton(
                  key: const Key('day-event-add'),
                  primary: true,
                  icon: Icons.favorite,
                  label: AppStrings.calendarAddEvent,
                  onPressed: () => _openNew(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayEventRow extends StatelessWidget {
  const _DayEventRow({super.key, required this.event, this.onTap});

  final CalendarEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timeText = event.allDay
        ? AppStrings.calendarAllDayChip
        : timeLabel(event.starts);

    return Semantics(
      button: onTap != null,
      label: '${event.title}, $timeText',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BevelBox(
              color: event.color.colorOf(colors),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      timeText,
                      style: AppTextStyles.caption.copyWith(color: colors.ink),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      event.title,
                      style: AppTextStyles.body2.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
