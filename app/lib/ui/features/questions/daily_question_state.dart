/// The four states [DailyQuestionWindow] renders — pure, so it's cheap to
/// unit test independent of the widget or view model.
enum DailyQuestionState {
  /// Still fetching `/api/question/today` for the first time.
  loading,

  /// I haven't answered today yet.
  unanswered,

  /// I've answered; my partner hasn't (or the server hasn't told me they
  /// have — see the blind). Anti-features rule: no streaks, no "day 4
  /// missed" pressure — this state just quietly waits.
  waiting,

  /// Both partners have answered — both answers are visible.
  revealed,
}

/// Derives the display state from the raw `both_answered`/`my_answer`
/// facts, matching the server response shape 1:1 so it's testable without
/// constructing a full [DailyQuestion].
DailyQuestionState dailyQuestionState({
  required bool hasQuestion,
  required bool bothAnswered,
  required bool hasMyAnswer,
}) {
  if (!hasQuestion) return DailyQuestionState.loading;
  if (bothAnswered) return DailyQuestionState.revealed;
  if (hasMyAnswer) return DailyQuestionState.waiting;
  return DailyQuestionState.unanswered;
}
