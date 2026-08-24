import 'package:flutter/material.dart';

import '../../../domain/models/pet_event.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/retro_window.dart';
import 'pet_view_model.dart';

/// Per-event-type copy for the story list. Local to this file rather than
/// AppStrings on purpose: app_strings.dart is owned by another agent this
/// wave, and this table only needs to cover the handful of `type` values
/// the server actually writes (server/migrations/6_pet.go: feed, pet,
/// dress, rename) plus a generic fallback for whatever comes next.
const Map<String, String> _petEventLines = {
  'feed': 'gave them a snack ♡︎',
  'pet': 'gave them a cuddle',
  'dress': 'changed how they look',
  'rename': 'gave them a new name',
};

/// Shown for any `type` not in [_petEventLines] — an older/newer server
/// writing something this build doesn't know about yet. Never an error.
const _petEventFallbackLine = 'did something sweet for them ⋆';

String petEventLine(PetEvent event) =>
    _petEventLines[event.type] ?? _petEventFallbackLine;

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/// "just now" / "5m ago" / "2h ago" / "aug 21" — lowercase, and driven by
/// an explicit [now] rather than `DateTime.now()` so it's testable at any
/// hour (matches the rest of pet_state.dart's clock discipline).
String petEventRelativeTime(DateTime when, DateTime now) {
  final diff = now.difference(when).isNegative
      ? Duration.zero
      : now.difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${_months[when.month - 1]} ${when.day}';
}

/// The "story" dialog: the shared pet's append-only care log, newest first
/// (AppStrings.petHistoryButton opens this from [PetWindow]). Kicks off
/// [PetViewModel.loadHistory] on open — a no-op if the story was already
/// loaded this session.
Future<void> showPetHistoryDialog(
  BuildContext context, {
  required PetViewModel viewModel,
}) {
  viewModel.loadHistory();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => _PetHistoryContent(viewModel: viewModel),
      ),
    ),
  );
}

class _PetHistoryContent extends StatelessWidget {
  const _PetHistoryContent({required this.viewModel});

  final PetViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final events = viewModel.history;
    final showSpinner = viewModel.historyLoading && events.isEmpty;
    final showEmpty = !showSpinner && events.isEmpty;

    return RetroWindow(
      title: AppStrings.petHistoryTitle,
      onClose: () => Navigator.of(context).pop(),
      child: SizedBox(
        width: 280,
        child: showSpinner
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : showEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  AppStrings.petHistoryEmpty,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body2.copyWith(color: colors.ink),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 12, color: colors.chromeAlt),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return _PetEventRow(
                      event: event,
                      now: viewModel.clockNow,
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _PetEventRow extends StatelessWidget {
  const _PetEventRow({required this.event, required this.now});

  final PetEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            petEventLine(event),
            style: AppTextStyles.body2.copyWith(color: colors.ink),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          petEventRelativeTime(event.created, now),
          style: AppTextStyles.caption.copyWith(color: colors.accent2),
        ),
      ],
    );
  }
}
