import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/notifications/kehai_notifier.dart';
import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/prefs_service.dart';

void main() {
  group('KehaiSound catalogue', () {
    test('every non-silent sound points at both of its bundled files', () {
      for (final sound in KehaiSound.values) {
        if (sound.isSilent) continue;
        expect(sound.assetPath, 'assets/sounds/${sound.id}.wav');
        // res/raw names must be lowercase letters, digits and underscores —
        // anything else fails the Android resource compiler at build time.
        expect(sound.androidResource, matches(RegExp(r'^[a-z0-9_]+$')));
        expect(sound.androidResource, startsWith('kehai_'));
      }
    });

    test('the picker offers all four voices plus silence', () {
      expect(KehaiSound.pickable, hasLength(5));
      expect(KehaiSound.pickable, contains(KehaiSound.silent));
    });

    test('an unknown or missing id falls back to the caller default', () {
      expect(
        KehaiSound.byId(null, fallback: KehaiSound.chime),
        KehaiSound.chime,
      );
      expect(
        KehaiSound.byId('trombone', fallback: KehaiSound.pop),
        KehaiSound.pop,
      );
      expect(
        KehaiSound.byId('sparkle', fallback: KehaiSound.pop),
        KehaiSound.sparkle,
      );
    });
  });

  group('KehaiEventKind', () {
    test('ships the locked defaults', () {
      expect(KehaiEventKind.ping.defaultSound, KehaiSound.sparkle);
      expect(KehaiEventKind.doodle.defaultSound, KehaiSound.pop);
      expect(KehaiEventKind.instant.defaultSound, KehaiSound.chime);
      expect(KehaiEventKind.reveal.defaultSound, KehaiSound.chime);
    });

    test('mood is deliberately not an event kind', () {
      // Ambient stays ambient — see KehaiEventKind's doc comment. This test
      // exists so adding one has to be a decision, not a slip.
      expect(KehaiEventKind.values.map((k) => k.id), <String>[
        'ping',
        'doodle',
        'instant',
        'reveal',
      ]);
    });

    test('byId round-trips and rejects strangers', () {
      for (final kind in KehaiEventKind.values) {
        expect(KehaiEventKind.byId(kind.id), kind);
      }
      expect(KehaiEventKind.byId('mood'), isNull);
    });
  });

  group('Android channel ids', () {
    test('carry the sound, because a channel sound is immutable', () {
      expect(
        KehaiNotifier.channelIdFor(KehaiEventKind.ping, KehaiSound.sparkle),
        'kehai_evt_ping_sparkle',
      );
      // Different sound → different channel, which is the whole mechanism.
      expect(
        KehaiNotifier.channelIdFor(KehaiEventKind.ping, KehaiSound.purr),
        isNot(
          KehaiNotifier.channelIdFor(KehaiEventKind.ping, KehaiSound.sparkle),
        ),
      );
      // Different event → different channel, so muting one doesn't mute all.
      expect(
        KehaiNotifier.channelIdFor(KehaiEventKind.doodle, KehaiSound.sparkle),
        isNot(
          KehaiNotifier.channelIdFor(KehaiEventKind.ping, KehaiSound.sparkle),
        ),
      );
    });

    test('every event+sound pair is unique', () {
      final ids = <String>{};
      for (final kind in KehaiEventKind.values) {
        for (final sound in KehaiSound.values) {
          ids.add(KehaiNotifier.channelIdFor(kind, sound));
        }
      }
      expect(
        ids,
        hasLength(KehaiEventKind.values.length * KehaiSound.values.length),
      );
    });
  });

  group('sound preference round-trip', () {
    /// `supportedOverride: false` keeps every platform call out of this —
    /// what's under test is the persistence + defaulting, which is pure.
    Future<KehaiNotifier> notifier() async =>
        KehaiNotifier(prefs: await PrefsService.create(), supportedOverride: false);

    test('unset events report their own default', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await notifier();
      for (final kind in KehaiEventKind.values) {
        expect(n.soundFor(kind), kind.defaultSound);
      }
    });

    test('a chosen sound survives a fresh notifier and prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await notifier();
      await first.setSound(KehaiEventKind.ping, KehaiSound.purr);

      final second = await notifier();
      expect(second.soundFor(KehaiEventKind.ping), KehaiSound.purr);
      // …and only that event moved.
      expect(second.soundFor(KehaiEventKind.doodle), KehaiSound.pop);
    });

    test('silence is a real choice, not "unset"', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await notifier();
      await n.setSound(KehaiEventKind.reveal, KehaiSound.silent);
      expect((await notifier()).soundFor(KehaiEventKind.reveal).isSilent, isTrue);
    });

    test('a pref written by some other build degrades to the default', () async {
      SharedPreferences.setMockInitialValues({
        'notification_sound_ping': 'foghorn',
      });
      expect((await notifier()).soundFor(KehaiEventKind.ping), KehaiSound.sparkle);
    });

    test('the prefs key shape is what the background isolate reads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      await prefs.setNotificationSound('ping', 'chime');
      expect(prefs.notificationSound('ping'), 'chime');
      expect(prefs.notificationSound('doodle'), isNull);
    });
  });
}
