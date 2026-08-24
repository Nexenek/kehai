import 'package:couples_app/domain/models/ambient_line.dart';
import 'package:couples_app/domain/notification_icon.dart';
import 'package:flutter_test/flutter_test.dart';

AmbientLine _line(AmbientLineKind kind, [String text = '']) =>
    AmbientLine(kind: kind, text: text);

void main() {
  group('notificationIconFor', () {
    test('null line -> heart', () {
      expect(notificationIconFor(null), 'ic_stat_heart');
    });

    test('nowPlaying -> music, regardless of the marquee text', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.nowPlaying, '♪ Marigold — yeule')),
        'ic_stat_music',
      );
    });

    test('asleep -> sleep', () {
      expect(notificationIconFor(_line(AmbientLineKind.asleep)), 'ic_stat_sleep');
    });

    test('away -> away', () {
      expect(notificationIconFor(_line(AmbientLineKind.away)), 'ic_stat_away');
    });

    test('atComputer -> heart (presence-only, no bespoke glyph)', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.atComputer)),
        'ic_stat_heart',
      );
    });

    test('onPhone -> heart (presence-only, no bespoke glyph)', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.onPhone)),
        'ic_stat_heart',
      );
    });

    group('activity keyword matches', () {
      const cases = <String, String>{
        'coding ⌨︎': 'ic_stat_code',
        'in a terminal': 'ic_stat_code',
        'scrolling TikTok': 'ic_stat_scroll',
        'watching YouTube': 'ic_stat_watch',
        'watching Netflix': 'ic_stat_watch',
        'on Netflix': 'ic_stat_watch',
        'on Twitch': 'ic_stat_watch',
        'gaming': 'ic_stat_game',
        'playing a game': 'ic_stat_game',
        'chatting on Discord ✉︎': 'ic_stat_chat',
        'texting ✉︎': 'ic_stat_chat',
        'on a call ☎︎': 'ic_stat_chat',
        'checking email ✉︎': 'ic_stat_chat',
        'taking photos ◉': 'ic_stat_photo',
        'listening to a podcast': 'ic_stat_music',
      };

      for (final entry in cases.entries) {
        test('"${entry.key}" -> ${entry.value}', () {
          expect(
            notificationIconFor(_line(AmbientLineKind.activity, entry.key)),
            entry.value,
          );
        });
      }
    });

    test('activity matching is case-insensitive', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.activity, 'CODING IN VS CODE')),
        'ic_stat_code',
      );
    });

    test('unmapped activity text falls back to heart (e.g. navigating)', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.activity, 'navigating ➤')),
        'ic_stat_heart',
      );
    });

    test('unmapped generic browsing activity falls back to heart', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.activity, 'browsing ☁︎')),
        'ic_stat_heart',
      );
    });

    test('empty activity text falls back to heart', () {
      expect(
        notificationIconFor(_line(AmbientLineKind.activity, '')),
        'ic_stat_heart',
      );
    });

    test('every possible result is in notificationIconNames', () {
      final results = <String>{
        notificationIconFor(null),
        for (final kind in AmbientLineKind.values)
          notificationIconFor(_line(kind, 'gaming')),
      };
      for (final icon in results) {
        expect(notificationIconNames.contains(icon), isTrue, reason: icon);
      }
    });
  });
}
