import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/questions/daily_question_state.dart';

void main() {
  group('dailyQuestionState', () {
    test('no question yet is loading', () {
      expect(
        dailyQuestionState(
          hasQuestion: false,
          bothAnswered: false,
          hasMyAnswer: false,
        ),
        DailyQuestionState.loading,
      );
    });

    test('a question with no answer yet is unanswered', () {
      expect(
        dailyQuestionState(
          hasQuestion: true,
          bothAnswered: false,
          hasMyAnswer: false,
        ),
        DailyQuestionState.unanswered,
      );
    });

    test('I answered, partner has not: waiting', () {
      expect(
        dailyQuestionState(
          hasQuestion: true,
          bothAnswered: false,
          hasMyAnswer: true,
        ),
        DailyQuestionState.waiting,
      );
    });

    test('both answered: revealed, regardless of hasMyAnswer flag', () {
      expect(
        dailyQuestionState(
          hasQuestion: true,
          bothAnswered: true,
          hasMyAnswer: true,
        ),
        DailyQuestionState.revealed,
      );
      expect(
        dailyQuestionState(
          hasQuestion: true,
          bothAnswered: true,
          hasMyAnswer: false,
        ),
        DailyQuestionState.revealed,
        reason:
            'the server only ever reports both_answered=true when it is '
            'also true for me, but the pure function should not assume that',
      );
    });
  });
}
