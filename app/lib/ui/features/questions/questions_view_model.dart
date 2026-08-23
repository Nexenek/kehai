import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/question_repository.dart';
import '../../../domain/models/daily_question.dart';
import '../../core/strings/app_strings.dart';
import 'daily_question_state.dart';

/// Drives the daily-question RetroWindow: fetches today's question, submits
/// (and edits) my answer, and refreshes on realtime pings so the reveal
/// lands live the moment my partner answers — no polling, no pull-to-
/// refresh needed.
class QuestionsViewModel extends ChangeNotifier {
  QuestionsViewModel({required QuestionRepository questionRepository})
    : _questionRepository = questionRepository;

  final QuestionRepository _questionRepository;

  bool isLoading = true;
  bool isSubmitting = false;
  DailyQuestion? question;
  String? error;

  /// True for exactly one build right after the partner's answer arrives
  /// live (as opposed to already being revealed on a fresh load) — the
  /// window uses this to play the one-time sparkle moment
  /// (design-language.md "one orchestrated moment per screen") and then
  /// calls [acknowledgeReveal] to clear it.
  bool justRevealed = false;

  UnsubscribeFunc? _unsub;

  /// False only until the very first `today()` call resolves — guards
  /// [justRevealed] so opening the window on a day that's already revealed
  /// (nothing "arrived live", it was just loaded) never triggers the
  /// sparkle; only a *transition* seen after that first load does.
  bool _hasLoadedOnce = false;

  DailyQuestionState get state => dailyQuestionState(
    hasQuestion: question != null,
    bothAnswered: question?.bothAnswered ?? false,
    hasMyAnswer: question?.myAnswer != null,
  );

  Future<void> init() async {
    await _refresh();
    _unsub = await _questionRepository.subscribe(_onRealtimeChange);
  }

  Future<void> _refresh() async {
    final wasRevealed = question?.bothAnswered ?? false;
    final isFirstLoad = !_hasLoadedOnce;
    try {
      question = await _questionRepository.today();
      error = null;
      if (!isFirstLoad && !wasRevealed && question!.bothAnswered) {
        justRevealed = true;
      }
    } catch (_) {
      error = AppStrings.questionsLoadFailed;
    }
    _hasLoadedOnce = true;
    isLoading = false;
    notifyListeners();
  }

  Future<void> _onRealtimeChange() => _refresh();

  /// Submits [text] as my answer for today — first submission or an edit,
  /// same call either way (the route upserts).
  Future<void> submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isSubmitting) return;
    isSubmitting = true;
    error = null;
    notifyListeners();
    try {
      await _questionRepository.answer(trimmed);
      await _refresh();
    } catch (_) {
      error = AppStrings.questionsSubmitFailed;
      isSubmitting = false;
      notifyListeners();
      return;
    }
    isSubmitting = false;
    notifyListeners();
  }

  void acknowledgeReveal() {
    if (!justRevealed) return;
    justRevealed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
