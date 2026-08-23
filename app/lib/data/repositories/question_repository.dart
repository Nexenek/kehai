import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/daily_question.dart';

/// Wraps the custom `/api/question/today` and `/api/question/answer` routes
/// (server/questions.go) — the daily-question blind reveal
/// (kb/features.md). Deliberately does NOT talk to the `answers`/
/// `question_days` collections directly for reads: the route does its own
/// server-side blind check on top of the collections' own ViewRule, so
/// going through it keeps the app on the belt-and-suspenders path rather
/// than depending solely on the collection rule.
class QuestionRepository {
  QuestionRepository(this._pb);

  final PocketBase _pb;

  Future<DailyQuestion> today() async {
    final json = await _pb.send<Map<String, dynamic>>(
      '/api/question/today',
      method: 'GET',
    );
    return DailyQuestion.fromJson(json);
  }

  /// Upserts the caller's own answer for today — submitting again (e.g. an
  /// edit before the reveal) just replaces the text.
  Future<void> answer(String text) {
    return _pb.send<Map<String, dynamic>>(
      '/api/question/answer',
      method: 'POST',
      body: {'text': text},
    );
  }

  /// Realtime nudge for the reveal moment: subscribes to the whole
  /// `answers` topic and calls [onChange] on every create/update event PB
  /// delivers. It deliberately doesn't try to parse the raw event into a
  /// [DailyQuestion] itself — the event only carries one row, and what the
  /// caller actually needs after it fires is a fresh `today()` (new
  /// `partner_answer`/`both_answered`), so [onChange] takes no arguments by
  /// design and callers should just re-fetch.
  ///
  /// PB only ever delivers events for records that pass the `answers`
  /// collection's ViewRule for the subscribed user (same rule a direct
  /// fetch is checked against — see migrations/9_questions.go), so this
  /// can't leak the partner's answer any earlier than a plain refresh
  /// would've shown it; it just means we don't have to poll to catch the
  /// moment it opens up.
  Future<UnsubscribeFunc> subscribe(void Function() onChange) async {
    try {
      return await _pb.collection('answers').subscribe('*', (e) {
        onChange();
      });
    } catch (_) {
      return () async {};
    }
  }
}
