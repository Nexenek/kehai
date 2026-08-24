import 'package:flutter/material.dart';

import '../../../domain/models/mood.dart';
import '../../../domain/models/mood_entry.dart';
import '../../../domain/mood_jar_grouping.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/retro_window.dart';
import 'jar_painter.dart';
import 'mood_jar_view_model.dart';

/// Every AppStrings.jar* string already exists (app_strings.dart's "the
/// mood jar" section) — these two are the only pieces of jar copy that
/// don't, since a row needs to say who felt it and that wasn't part of the
/// wave that landed the rest of the strings. Kept private rather than
/// added to app_strings.dart per this wave's file boundaries.
const _jarYou = 'you';
const _jarPartner = 'partner';

const _monthAbbr = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// "aug 21" — lowercase, no year (a 90-day jar never needs one). Only used
/// for [JarDayKind.older]; today/yesterday come straight from AppStrings.
String _shortDate(DateTime day) => '${_monthAbbr[day.month - 1]} ${day.day}';

String _dayHeading(JarDayGroup group) {
  switch (group.kind) {
    case JarDayKind.today:
      return AppStrings.jarDayToday;
    case JarDayKind.yesterday:
      return AppStrings.jarDayYesterday;
    case JarDayKind.older:
      return _shortDate(group.day);
  }
}

/// Looks up [id] in [MoodCatalog] without [MoodCatalog.byId]'s "fall back
/// to happy" behavior — an unrecognized mood id in the jar should read as
/// unrecognized (ink, no kaomoji), not silently masquerade as a real mood
/// nobody actually picked.
Mood? _moodOrNull(String id) {
  for (final mood in MoodCatalog.all) {
    if (mood.id == id) return mood;
  }
  return null;
}

/// The mood jar RetroWindow (kb/features.md "Mood jar / mood history"): a
/// painted jar of beads — one per recent mood change, newest on top — over
/// the same history as a grouped-by-day list underneath.
class MoodJarWindow extends StatelessWidget {
  const MoodJarWindow({super.key, required this.viewModel, this.onClose});

  final MoodJarViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final groups = viewModel.dayGroups;

        return RetroWindow(
          title: AppStrings.jarTitle,
          onClose: onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const Key('jar-glass'),
                height: 150,
                child: CustomPaint(
                  painter: JarPainter(
                    // Oldest first: the painter fills rows bottom-up and
                    // draws in list order, so the last color both sits
                    // highest and paints last (on top) — see the painter's
                    // doc comment.
                    beadColors: [
                      for (final entry in viewModel.entries.reversed)
                        _moodOrNull(entry.mood)?.colorOf(colors) ?? colors.ink,
                    ],
                    ink: colors.ink,
                    shine: colors.sky,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    AppStrings.jarEmpty,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                )
              else
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      _dayHeading(group),
                      style: AppTextStyles.caption.copyWith(
                        color: colors.chromeAlt,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final entry in group.entries)
                    _JarEntryRow(
                      entry: entry,
                      isMine: entry.userId == viewModel.myUserId,
                    ),
                ],
            ],
          ),
        );
      },
    );
  }
}

/// One bead's row in the list below the jar: kaomoji, mood label + who,
/// and the optional note underneath.
class _JarEntryRow extends StatelessWidget {
  const _JarEntryRow({required this.entry, required this.isMine});

  final MoodEntry entry;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mood = _moodOrNull(entry.mood);
    final color = mood?.colorOf(colors) ?? colors.ink;
    final who = isMine ? _jarYou : _jarPartner;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: BevelBox(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // An unrecognized mood id still gets a face — just a
              // confused one, in ink, rather than no kaomoji at all.
              mood?.kaomoji ?? '(・_・?)',
              style: AppTextStyles.body2.copyWith(color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${mood?.label ?? entry.mood} · $who',
                    style: AppTextStyles.body2.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (entry.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.note,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.chromeAlt,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
