import 'package:flutter/material.dart';

import '../../../domain/calendar_math.dart';
import '../../../domain/day_math.dart' show friendlyDate;
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/event_color.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';

/// The result of the event add/edit dialog — ready to hand straight to
/// [CalendarViewModel.addEvent]/`updateEvent`.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.starts,
    required this.ends,
    required this.allDay,
    required this.notes,
    required this.color,
  });

  final String title;
  final DateTime starts;
  final DateTime? ends;
  final bool allDay;
  final String notes;
  final EventColor color;
}

/// Shows the RetroWindow-styled add/edit dialog, mirroring
/// `countdown_dialog.dart`/`note_dialog.dart`. Pass [existing] to edit (and
/// get a delete button); omit it to create a new event, seeded with
/// [initialDate] (defaults to now) — the day the caller tapped.
Future<void> showEventDialog(
  BuildContext context, {
  CalendarEvent? existing,
  DateTime? initialDate,
  required ValueChanged<EventDraft> onSave,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: _EventDialogContent(
        existing: existing,
        initialDate: initialDate,
        onSave: onSave,
        onDelete: onDelete,
      ),
    ),
  );
}

class _EventDialogContent extends StatefulWidget {
  const _EventDialogContent({
    this.existing,
    this.initialDate,
    required this.onSave,
    this.onDelete,
  });

  final CalendarEvent? existing;
  final DateTime? initialDate;
  final ValueChanged<EventDraft> onSave;
  final VoidCallback? onDelete;

  @override
  State<_EventDialogContent> createState() => _EventDialogContentState();
}

class _EventDialogContentState extends State<_EventDialogContent> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late DateTime _starts;
  DateTime? _ends;
  late bool _allDay;
  late EventColor _color;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _allDay = existing?.allDay ?? false;
    _color = existing?.color ?? EventColor.pink;
    final seed = existing?.starts ?? widget.initialDate ?? DateTime.now();
    _starts = DateTime(seed.year, seed.month, seed.day, seed.hour, seed.minute);
    _ends = existing?.ends;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickStartsDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _starts,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _starts = DateTime(picked.year, picked.month, picked.day, _starts.hour, _starts.minute);
      if (_ends != null && _ends!.isBefore(_starts)) _ends = null;
    });
  }

  Future<void> _pickStartsTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _starts.hour, minute: _starts.minute),
    );
    if (picked == null) return;
    setState(() {
      _starts = DateTime(
        _starts.year,
        _starts.month,
        _starts.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickEndsDate() async {
    final seed = _ends ?? _starts;
    final picked = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: _starts,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final base = _ends ?? _starts;
      _ends = DateTime(picked.year, picked.month, picked.day, base.hour, base.minute);
    });
  }

  Future<void> _pickEndsTime() async {
    final base = _ends ?? _starts;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (picked == null) return;
    setState(() {
      final day = _ends ?? _starts;
      _ends = DateTime(day.year, day.month, day.day, picked.hour, picked.minute);
    });
  }

  void _toggleEnds(bool add) {
    setState(() {
      _ends = add ? _starts.add(const Duration(hours: 1)) : null;
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final starts = _allDay ? dateOnly(_starts) : _starts;
    final ends = _ends == null ? null : (_allDay ? dateOnly(_ends!) : _ends);
    widget.onSave(
      EventDraft(
        title: title,
        starts: starts,
        ends: ends,
        allDay: _allDay,
        notes: _notesController.text.trim(),
        color: _color,
      ),
    );
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.onDelete?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEdit = widget.existing != null;

    return RetroWindow(
      title: isEdit
          ? AppStrings.calendarEditEventTitle
          : AppStrings.calendarNewEventTitle,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.calendarEventTitleLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _titleController,
            style: AppTextStyles.body1,
            decoration: const InputDecoration(
              hintText: AppStrings.calendarEventTitleHint,
            ),
            autofocus: !isEdit,
          ),
          const SizedBox(height: 12),
          _toggleRow(
            key: const Key('event-dialog-all-day'),
            label: AppStrings.calendarAllDayLabel,
            selected: _allDay,
            onTap: () => setState(() => _allDay = !_allDay),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.calendarStartsLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          _dateTimeRow(
            dateKey: const Key('event-dialog-starts-date'),
            timeKey: const Key('event-dialog-starts-time'),
            value: _starts,
            onTapDate: _pickStartsDate,
            onTapTime: _allDay ? null : _pickStartsTime,
          ),
          const SizedBox(height: 12),
          _toggleRow(
            key: const Key('event-dialog-ends-toggle'),
            label: AppStrings.calendarEndsToggle,
            selected: _ends != null,
            onTap: () => _toggleEnds(_ends == null),
          ),
          if (_ends != null) ...[
            const SizedBox(height: 8),
            Text(
              AppStrings.calendarEndsLabel,
              style: AppTextStyles.caption.copyWith(color: colors.ink),
            ),
            const SizedBox(height: 4),
            _dateTimeRow(
              dateKey: const Key('event-dialog-ends-date'),
              timeKey: const Key('event-dialog-ends-time'),
              value: _ends!,
              onTapDate: _pickEndsDate,
              onTapTime: _allDay ? null : _pickEndsTime,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            AppStrings.calendarNotesLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _notesController,
            style: AppTextStyles.body1,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: AppStrings.calendarNotesHint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.calendarColorLabel,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
          const SizedBox(height: 6),
          Row(
            children: EventColor.values.map((c) {
              final selected = c == _color;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  key: Key('event-dialog-color-${c.name}'),
                  onTap: () => setState(() => _color = c),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: c.name,
                      child: BevelBox(
                        color: c.colorOf(colors),
                        style: selected ? BevelStyle.sunken : BevelStyle.raised,
                        thickness: selected ? 3 : 2,
                        padding: const EdgeInsets.all(10),
                        child: const SizedBox(width: 16, height: 16),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (isEdit)
                PixelButton(
                  label: AppStrings.calendarDeleteEvent,
                  onPressed: _delete,
                ),
              const Spacer(),
              PixelButton(
                primary: true,
                label: AppStrings.calendarSaveEvent,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: BevelBox(
            color: selected ? colors.chrome : colors.surface,
            style: selected ? BevelStyle.sunken : BevelStyle.raised,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected ? '☑' : '☐',
                  style: AppTextStyles.caption.copyWith(color: colors.ink),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateTimeRow({
    required Key dateKey,
    required Key timeKey,
    required DateTime value,
    required VoidCallback onTapDate,
    VoidCallback? onTapTime,
  }) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: dateKey,
            onTap: onTapDate,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BevelBox(
                color: colors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Text(
                  friendlyDate(value),
                  style: AppTextStyles.body1.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
        ),
        if (onTapTime != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            key: timeKey,
            onTap: onTapTime,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BevelBox(
                color: colors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Text(
                  timeLabel(value),
                  style: AppTextStyles.body1.copyWith(color: colors.ink),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
