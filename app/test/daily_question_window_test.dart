import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/question_repository.dart';
import 'package:couples_app/domain/models/daily_question.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/questions/daily_question_window.dart';
import 'package:couples_app/ui/features/questions/questions_view_model.dart';

/// A repository whose `today()` returns whatever `response` currently holds
/// — `answer()` updates it in place, the same "my_answer now set" effect
/// the real route's upsert has, so a submit-then-refresh round trip in the
/// view model actually changes what the window renders.
class _StubQuestions extends QuestionRepository {
  _StubQuestions(this.response) : super(PocketBase('https://x.invalid'));

  DailyQuestion response;
  final submittedTexts = <String>[];

  @override
  Future<DailyQuestion> today() async => response;

  @override
  Future<void> answer(String text) async {
    submittedTexts.add(text);
    response = DailyQuestion(
      date: response.date,
      questionEn: response.questionEn,
      questionPl: response.questionPl,
      myAnswer: text,
      partnerAnswer: response.partnerAnswer,
      bothAnswered: response.bothAnswered,
    );
  }

  @override
  Future<UnsubscribeFunc> subscribe(void Function() onChange) async {
    return () async {};
  }
}

const _en = "What's a small moment from this week?";
const _pl = 'Jaka drobna chwila z tego tygodnia?';

DailyQuestion _q({
  String? myAnswer,
  String? partnerAnswer,
  bool bothAnswered = false,
}) => DailyQuestion(
  date: '2026-08-23',
  questionEn: _en,
  questionPl: _pl,
  myAnswer: myAnswer,
  partnerAnswer: partnerAnswer,
  bothAnswered: bothAnswered,
);

Future<QuestionsViewModel> _pumpWindow(
  WidgetTester tester,
  DailyQuestion response,
) async {
  final viewModel = QuestionsViewModel(
    questionRepository: _StubQuestions(response),
  );
  await viewModel.init();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: DailyQuestionWindow(viewModel: viewModel)),
    ),
  );
  await tester.pump();
  return viewModel;
}

void main() {
  testWidgets('unanswered: shows both languages and an empty input', (
    tester,
  ) async {
    await _pumpWindow(tester, _q());

    expect(find.text(AppStrings.questionsTitle), findsOneWidget);
    expect(find.text(_en), findsOneWidget);
    expect(find.text(_pl), findsOneWidget);
    expect(find.text(AppStrings.questionsSubmit), findsOneWidget);
    expect(find.text(AppStrings.questionsWaitingTitle), findsNothing);
    expect(find.text(AppStrings.questionsYourAnswerLabel), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('waiting: sealed message shown, my answer pre-filled', (
    tester,
  ) async {
    await _pumpWindow(tester, _q(myAnswer: 'pierogi, obviously'));

    expect(find.text(_en), findsOneWidget);
    expect(find.text(_pl), findsOneWidget);
    expect(find.text(AppStrings.questionsWaitingTitle), findsOneWidget);
    expect(find.text(AppStrings.questionsWaitingBody), findsOneWidget);
    expect(find.text(AppStrings.questionsUpdateAnswer), findsOneWidget);
    expect(find.text(AppStrings.questionsYourAnswerLabel), findsNothing);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'pierogi, obviously');
  });

  testWidgets('revealed: both answers shown side by side, no input', (
    tester,
  ) async {
    await _pumpWindow(
      tester,
      _q(
        myAnswer: 'pierogi, obviously',
        partnerAnswer: 'żurek, for the record',
        bothAnswered: true,
      ),
    );

    expect(find.text(_en), findsOneWidget);
    expect(find.text(_pl), findsOneWidget);
    expect(find.text(AppStrings.questionsRevealedTitle), findsOneWidget);
    expect(find.text(AppStrings.questionsYourAnswerLabel), findsOneWidget);
    expect(find.text(AppStrings.questionsPartnerAnswerLabel), findsOneWidget);
    expect(find.text('pierogi, obviously'), findsOneWidget);
    expect(find.text('żurek, for the record'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(AppStrings.questionsSubmit), findsNothing);
  });

  testWidgets(
    'submitting calls through the view model and flips to waiting',
    (tester) async {
      final stub = _StubQuestions(_q());
      final viewModel = QuestionsViewModel(questionRepository: stub);
      await viewModel.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: DailyQuestionWindow(viewModel: viewModel)),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'pierogi, obviously');
      await tester.tap(find.text(AppStrings.questionsSubmit));
      await tester.pumpAndSettle();

      expect(stub.submittedTexts, ['pierogi, obviously']);
      expect(find.text(AppStrings.questionsWaitingTitle), findsOneWidget);
      expect(find.text(AppStrings.questionsUpdateAnswer), findsOneWidget);
    },
  );
}
