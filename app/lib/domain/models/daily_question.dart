import 'package:flutter/foundation.dart';

/// The response shape of `GET /api/question/today` (server/questions.go) —
/// today's prompt in both languages, plus each partner's answer.
///
/// [partnerAnswer] is null until [bothAnswered] is true: the blind reveal
/// (kb/features.md "Daily question, blind reveal") is enforced server-side
/// (see the answers collection's ViewRule in
/// server/migrations/9_questions.go plus the route's own belt-and-suspenders
/// check), so this model never even has the chance to render a partner
/// answer early — the server simply never sends it.
@immutable
class DailyQuestion {
  const DailyQuestion({
    required this.date,
    required this.questionEn,
    required this.questionPl,
    required this.myAnswer,
    required this.partnerAnswer,
    required this.bothAnswered,
  });

  /// YYYY-MM-DD, server clock (UTC) — see questions.go's `todayDate`.
  final String date;
  final String questionEn;
  final String questionPl;

  /// Null until the caller has answered today.
  final String? myAnswer;

  /// Null until BOTH partners have answered — see the class doc.
  final String? partnerAnswer;
  final bool bothAnswered;

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      date: json['date'] as String? ?? '',
      questionEn: json['question_en'] as String? ?? '',
      questionPl: json['question_pl'] as String? ?? '',
      myAnswer: json['my_answer'] as String?,
      partnerAnswer: json['partner_answer'] as String?,
      bothAnswered: json['both_answered'] as bool? ?? false,
    );
  }
}
