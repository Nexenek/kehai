import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/daily_question.dart';

void main() {
  group('DailyQuestion.fromJson', () {
    test('maps every field before anyone has answered', () {
      final q = DailyQuestion.fromJson({
        'date': '2026-08-23',
        'question_en': "What's a small moment from this week?",
        'question_pl': 'Jaka drobna chwila z tego tygodnia?',
        'my_answer': null,
        'partner_answer': null,
        'both_answered': false,
      });

      expect(q.date, '2026-08-23');
      expect(q.questionEn, "What's a small moment from this week?");
      expect(q.questionPl, 'Jaka drobna chwila z tego tygodnia?');
      expect(q.myAnswer, isNull);
      expect(q.partnerAnswer, isNull);
      expect(q.bothAnswered, isFalse);
    });

    test('my_answer set, partner_answer still null before the reveal', () {
      final q = DailyQuestion.fromJson({
        'date': '2026-08-23',
        'question_en': 'q',
        'question_pl': 'p',
        'my_answer': 'pierogi',
        'partner_answer': null,
        'both_answered': false,
      });

      expect(q.myAnswer, 'pierogi');
      expect(q.partnerAnswer, isNull);
      expect(q.bothAnswered, isFalse);
    });

    test('both answers present once revealed', () {
      final q = DailyQuestion.fromJson({
        'date': '2026-08-23',
        'question_en': 'q',
        'question_pl': 'p',
        'my_answer': 'pierogi',
        'partner_answer': 'żurek',
        'both_answered': true,
      });

      expect(q.myAnswer, 'pierogi');
      expect(q.partnerAnswer, 'żurek');
      expect(q.bothAnswered, isTrue);
    });

    test('missing keys fall back to safe empty defaults, not a throw', () {
      final q = DailyQuestion.fromJson(const {});

      expect(q.date, '');
      expect(q.questionEn, '');
      expect(q.questionPl, '');
      expect(q.myAnswer, isNull);
      expect(q.partnerAnswer, isNull);
      expect(q.bothAnswered, isFalse);
    });
  });
}
