import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/notifications/notification_decision.dart';
import 'package:couples_app/domain/models/ping.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';

/// The two suppression rules and the per-kind copy — the whole reason
/// `decideNotification` is a pure function instead of a method on the
/// notifier.
void main() {
  const me = 'user_me';
  const them = 'user_them';

  KehaiEvent event(
    KehaiEventKind kind, {
    String authorId = them,
    String partnerName = 'mati',
    PingKind? pingKind,
  }) => KehaiEvent(
    kind: kind,
    authorId: authorId,
    partnerName: partnerName,
    pingKind: pingKind,
  );

  NotificationRequest? decide(
    KehaiEvent e, {
    bool foreground = false,
    String myUserId = me,
  }) => decideNotification(
    event: e,
    myUserId: myUserId,
    appInForeground: foreground,
  );

  group('self-echo suppression', () {
    test('my own event never notifies me', () {
      for (final kind in KehaiEventKind.values) {
        expect(
          decide(event(kind, authorId: me, pingKind: PingKind.kiss)),
          isNull,
          reason: '$kind authored by me should stay quiet',
        );
      }
    });

    test("my partner's event does notify me", () {
      for (final kind in KehaiEventKind.values) {
        expect(decide(event(kind)), isNotNull, reason: '$kind from them');
      }
    });

    test('an unattributed event notifies rather than vanishing', () {
      // Better a stray notification than a silently dropped doodle.
      expect(decide(event(KehaiEventKind.doodle, authorId: '')), isNotNull);
    });

    test('an unknown session id treats everything as somebody else’s', () {
      expect(decide(event(KehaiEventKind.ping), myUserId: ''), isNotNull);
    });
  });

  group('foreground suppression', () {
    test('nothing notifies while the app is on screen here', () {
      for (final kind in KehaiEventKind.values) {
        expect(decide(event(kind), foreground: true), isNull);
      }
    });

    test('everything notifies once it is not', () {
      for (final kind in KehaiEventKind.values) {
        expect(decide(event(kind), foreground: false), isNotNull);
      }
    });
  });

  group('copy', () {
    test('each ping kind gets its own body', () {
      final bodies = <String>{};
      for (final pingKind in PingKind.values) {
        final request = decide(
          event(KehaiEventKind.ping, pingKind: pingKind),
        )!;
        expect(request.eventKind, KehaiEventKind.ping);
        expect(request.title, contains('mati'));
        bodies.add(request.body);
      }
      expect(bodies.length, PingKind.values.length, reason: 'all distinct');
      expect(
        decide(event(KehaiEventKind.ping, pingKind: PingKind.hug))!.body,
        contains('hug'),
      );
    });

    test('a ping with no kind falls back to "thinking"', () {
      expect(
        decide(event(KehaiEventKind.ping))!.body,
        AppStrings.notifyPingBody(PingKind.thinking),
      );
    });

    test('a nameless partner becomes "your person"', () {
      expect(
        decide(event(KehaiEventKind.doodle, partnerName: '   '))!.title,
        contains(AppStrings.notifyFallbackName),
      );
    });

    test('the name is trimmed, not pasted raw', () {
      expect(
        decide(event(KehaiEventKind.instant, partnerName: '  mati  '))!.title,
        AppStrings.notifyInstantTitle('mati'),
      );
    });

    test('the reveal headline is about the question, not the person', () {
      final request = decide(event(KehaiEventKind.reveal))!;
      expect(request.title, AppStrings.notifyRevealTitle);
      expect(request.body, contains('mati'));
    });

    test('every event kind produces a non-empty title and body', () {
      for (final kind in KehaiEventKind.values) {
        final request = decide(event(kind))!;
        expect(request.title, isNotEmpty);
        expect(request.body, isNotEmpty);
        expect(request.eventKind, kind);
      }
    });
  });
}
