import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/question_repository.dart';
import 'package:couples_app/domain/models/daily_question.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/questions/daily_question_state.dart';
import 'package:couples_app/ui/features/questions/questions_view_model.dart';

/// In-memory stand-in for the `/api/question/*` routes: hands back whatever
/// the test wires up for `today()`, records `answer()` calls, and can push
/// a realtime nudge like the partner's own client causes server-side.
class _FakeQuestions extends QuestionRepository {
  _FakeQuestions({required this.responses}) : super(PocketBase('https://x.invalid'));

  /// Queue of responses `today()` returns, one per call (last one repeats
  /// once exhausted) — lets a test script "day 1 unanswered, then after
  /// submit here's day 1 answered, then after realtime here's revealed".
  List<DailyQuestion> responses;
  int _todayCalls = 0;
  final submittedTexts = <String>[];
  bool failNextAnswer = false;
  bool failToday = false;
  void Function()? _listener;

  @override
  Future<DailyQuestion> today() async {
    if (failToday) throw ClientException(statusCode: 500);
    final index = _todayCalls < responses.length
        ? _todayCalls
        : responses.length - 1;
    _todayCalls++;
    return responses[index];
  }

  @override
  Future<void> answer(String text) async {
    if (failNextAnswer) {
      failNextAnswer = false;
      throw ClientException(statusCode: 500);
    }
    submittedTexts.add(text);
  }

  @override
  Future<UnsubscribeFunc> subscribe(void Function() onChange) async {
    _listener = onChange;
    return () async => _listener = null;
  }

  /// Simulates PB delivering a realtime event on the `answers` topic (the
  /// partner answering, in practice).
  void pushRealtime() => _listener?.call();

  bool get isSubscribed => _listener != null;
}

DailyQuestion _q({
  String? myAnswer,
  String? partnerAnswer,
  bool bothAnswered = false,
}) => DailyQuestion(
  date: '2026-08-23',
  questionEn: "What's a small moment from this week?",
  questionPl: 'Jaka drobna chwila z tego tygodnia?',
  myAnswer: myAnswer,
  partnerAnswer: partnerAnswer,
  bothAnswered: bothAnswered,
);

void main() {
  test('init loads unanswered state and subscribes for the reveal', () async {
    final questions = _FakeQuestions(responses: [_q()]);
    final viewModel = QuestionsViewModel(questionRepository: questions);

    await viewModel.init();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.state, DailyQuestionState.unanswered);
    expect(questions.isSubscribed, isTrue);
    expect(viewModel.justRevealed, isFalse);
  });

  test('submitting an answer moves to waiting', () async {
    final questions = _FakeQuestions(
      responses: [_q(), _q(myAnswer: 'pierogi, obviously')],
    );
    final viewModel = QuestionsViewModel(questionRepository: questions);
    await viewModel.init();

    await viewModel.submit('pierogi, obviously');

    expect(questions.submittedTexts, ['pierogi, obviously']);
    expect(viewModel.state, DailyQuestionState.waiting);
    expect(viewModel.question?.myAnswer, 'pierogi, obviously');
    expect(viewModel.question?.partnerAnswer, isNull);
  });

  test('whitespace-only submissions are ignored, not sent', () async {
    final questions = _FakeQuestions(responses: [_q()]);
    final viewModel = QuestionsViewModel(questionRepository: questions);
    await viewModel.init();

    await viewModel.submit('   ');

    expect(questions.submittedTexts, isEmpty);
    expect(viewModel.state, DailyQuestionState.unanswered);
  });

  test(
    "the partner answering live flips to revealed and flags the sparkle once",
    () async {
      final questions = _FakeQuestions(
        responses: [
          _q(myAnswer: 'pierogi'), // initial load: I've answered, waiting
          _q(
            myAnswer: 'pierogi',
            partnerAnswer: 'żurek',
            bothAnswered: true,
          ), // after the realtime nudge
        ],
      );
      final viewModel = QuestionsViewModel(questionRepository: questions);
      await viewModel.init();
      expect(viewModel.state, DailyQuestionState.waiting);
      expect(viewModel.justRevealed, isFalse);

      questions.pushRealtime();
      // subscribe's callback triggers an async refresh; let it settle.
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.state, DailyQuestionState.revealed);
      expect(viewModel.question?.partnerAnswer, 'żurek');
      expect(
        viewModel.justRevealed,
        isTrue,
        reason: 'this refresh is the one that flipped both_answered',
      );

      viewModel.acknowledgeReveal();
      expect(viewModel.justRevealed, isFalse);
    },
  );

  test(
    'loading already-revealed on a fresh init does not flag the sparkle',
    () async {
      final questions = _FakeQuestions(
        responses: [
          _q(myAnswer: 'pierogi', partnerAnswer: 'żurek', bothAnswered: true),
        ],
      );
      final viewModel = QuestionsViewModel(questionRepository: questions);

      await viewModel.init();

      expect(viewModel.state, DailyQuestionState.revealed);
      expect(
        viewModel.justRevealed,
        isFalse,
        reason: 'nothing "arrived live" — it was already revealed on load',
      );
    },
  );

  test('a failed submit leaves the draft state and reports honestly', () async {
    final questions = _FakeQuestions(responses: [_q()])
      ..failNextAnswer = true;
    final viewModel = QuestionsViewModel(questionRepository: questions);
    await viewModel.init();

    await viewModel.submit('pierogi');

    expect(viewModel.state, DailyQuestionState.unanswered);
    expect(viewModel.error, AppStrings.questionsSubmitFailed);
    expect(viewModel.isSubmitting, isFalse);
  });

  test('a failed initial load surfaces the load error, not a crash', () async {
    final questions = _FakeQuestions(responses: const [])..failToday = true;
    final viewModel = QuestionsViewModel(questionRepository: questions);

    await viewModel.init();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.question, isNull);
    expect(viewModel.error, AppStrings.questionsLoadFailed);
    expect(viewModel.state, DailyQuestionState.loading);
  });
}
