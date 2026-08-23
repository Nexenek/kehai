import 'package:flutter/material.dart';

import '../../../domain/models/daily_question.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'daily_question_state.dart';
import 'questions_view_model.dart';

/// The daily-question RetroWindow (kb/features.md "Daily question, blind
/// reveal"): the question in EN with PL underneath in smaller type — always
/// both, regardless of state — my answer input, the sealed waiting state,
/// and the side-by-side reveal with a one-time sparkle when the partner's
/// answer arrives live.
///
/// Self-contained, same as `InstantsWindow`/`PetWindow` — this batch builds
/// the feature but does NOT wire it into the home tray/layout (the
/// coordinator owns that composition this round). A caller just needs a
/// [QuestionsViewModel] wired to a real [QuestionRepository], with `init()`
/// already called.
///
/// Streak-free, pressure-free (kb/features.md anti-features): there is no
/// rendering path anywhere in this widget that mentions a missed day.
class DailyQuestionWindow extends StatefulWidget {
  const DailyQuestionWindow({super.key, required this.viewModel, this.onClose});

  final QuestionsViewModel viewModel;

  /// Makes the window's ♥ functional when shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  @override
  State<DailyQuestionWindow> createState() => _DailyQuestionWindowState();
}

class _DailyQuestionWindowState extends State<DailyQuestionWindow> {
  final _controller = TextEditingController();
  bool _controllerSeeded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seedControllerOnce(String? myAnswer) {
    if (_controllerSeeded) return;
    _controllerSeeded = true;
    _controller.text = myAnswer ?? '';
  }

  void _submit() {
    widget.viewModel.submit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final colors = context.colors;
        final viewModel = widget.viewModel;
        final question = viewModel.question;

        return RetroWindow(
          title: AppStrings.questionsTitle,
          onClose: widget.onClose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (question == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    viewModel.error ?? AppStrings.questionsLoading,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body2.copyWith(color: colors.ink),
                  ),
                )
              else
                ..._body(context, question),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, DailyQuestion question) {
    final colors = context.colors;
    final viewModel = widget.viewModel;
    final state = viewModel.state;

    _seedControllerOnce(question.myAnswer);

    return [
      // The prompt: EN always on top, PL always underneath in smaller
      // type — both languages, every time, regardless of state.
      Text(
        question.questionEn,
        style: AppTextStyles.body1.copyWith(color: colors.ink),
      ),
      const SizedBox(height: 4),
      Text(
        question.questionPl,
        style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
      ),
      const SizedBox(height: 12),
      if (state == DailyQuestionState.revealed)
        _RevealedAnswers(
          question: question,
          justRevealed: viewModel.justRevealed,
          onSparkleDone: viewModel.acknowledgeReveal,
        )
      else ...[
        if (state == DailyQuestionState.waiting) ...[
          Text(
            AppStrings.questionsWaitingTitle,
            style: AppTextStyles.body2.copyWith(color: colors.ink),
          ),
          Text(
            AppStrings.questionsWaitingBody,
            style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          style: AppTextStyles.body1,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: AppStrings.questionsAnswerHint,
          ),
        ),
      ],
      if (viewModel.error != null) ...[
        const SizedBox(height: 6),
        Text(
          viewModel.error!,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: colors.accent),
        ),
      ],
      if (state != DailyQuestionState.revealed) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: PixelButton(
            primary: true,
            label: state == DailyQuestionState.waiting
                ? AppStrings.questionsUpdateAnswer
                : AppStrings.questionsSubmit,
            onPressed: viewModel.isSubmitting ? null : _submit,
          ),
        ),
      ],
    ];
  }
}

class _RevealedAnswers extends StatefulWidget {
  const _RevealedAnswers({
    required this.question,
    required this.justRevealed,
    required this.onSparkleDone,
  });

  final DailyQuestion question;
  final bool justRevealed;
  final VoidCallback onSparkleDone;

  @override
  State<_RevealedAnswers> createState() => _RevealedAnswersState();
}

class _RevealedAnswersState extends State<_RevealedAnswers> {
  @override
  void initState() {
    super.initState();
    _scheduleAcknowledge();
  }

  @override
  void didUpdateWidget(covariant _RevealedAnswers oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleAcknowledge();
  }

  void _scheduleAcknowledge() {
    if (!widget.justRevealed) return;
    // One orchestrated moment (design-language.md), then it's done — the
    // sparkle only ever plays once per reveal.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.onSparkleDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.questionsRevealedTitle,
                style: AppTextStyles.body2.copyWith(color: colors.ink),
              ),
            ),
            if (widget.justRevealed && !reduceMotion)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) => Opacity(
                  opacity: 1 - value,
                  child: Transform.scale(scale: 1 + value * 0.6, child: child),
                ),
                child: Text(
                  '✧',
                  style: AppTextStyles.kaomojiMedium.copyWith(
                    color: colors.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 360;
            final tiles = [
              _AnswerTile(
                label: AppStrings.questionsYourAnswerLabel,
                text: widget.question.myAnswer ?? '',
                tint: colors.accent,
              ),
              _AnswerTile(
                label: AppStrings.questionsPartnerAnswerLabel,
                text: widget.question.partnerAnswer ?? '',
                tint: colors.accent2,
              ),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tiles[0],
                  const SizedBox(height: 8),
                  tiles[1],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 8),
                Expanded(child: tiles[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.label, required this.text, required this.tint});

  final String label;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BevelBox(
      style: BevelStyle.sunken,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: tint),
          ),
          const SizedBox(height: 4),
          Text(text, style: AppTextStyles.body2.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}
