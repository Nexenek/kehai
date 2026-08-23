import 'package:couples_app/data/services/presence/android/android_presence_mapper.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape the Kotlin `PresenceMonitor.snapshot()` sends over the
/// EventChannel. Built by hand here — no engine, no device.
Map<Object?, Object?> _snapshot({
  Object? battery,
  Object? charging,
  Object? screenOn = true,
  Object? screenOffSinceMillis,
  Object? mediaListenerEnabled = false,
  List<Object?>? sessions,
}) {
  return {
    'battery': battery,
    'charging': charging,
    'screen_on': screenOn,
    'screen_off_since_millis': screenOffSinceMillis,
    'media_listener_enabled': mediaListenerEnabled,
    'sessions': sessions ?? const [],
  };
}

Map<Object?, Object?> _session({
  String package = 'com.spotify.music',
  Object? label = 'Spotify',
  Object? title = 'Marigold',
  Object? artist = 'Periphery',
  Object? album = 'Juggernaut',
  int state = 3,
}) {
  return {
    'package': package,
    'label': label,
    'title': title,
    'artist': artist,
    'album': album,
    'state': state,
  };
}

void main() {
  group('AndroidPresenceSnapshot.fromChannel', () {
    test('parses a full payload', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          battery: 62,
          charging: true,
          screenOn: false,
          screenOffSinceMillis: 1000,
          mediaListenerEnabled: true,
          sessions: [_session()],
        ),
      );

      expect(snapshot.battery, 62);
      expect(snapshot.charging, isTrue);
      expect(snapshot.screenOn, isFalse);
      expect(snapshot.screenOffSinceMillis, 1000);
      expect(snapshot.mediaListenerEnabled, isTrue);
      expect(snapshot.sessions, hasLength(1));
    });

    test('degrades to empty for junk instead of throwing', () {
      expect(AndroidPresenceSnapshot.fromChannel(null), same(AndroidPresenceSnapshot.empty));
      expect(
        AndroidPresenceSnapshot.fromChannel('not a map'),
        same(AndroidPresenceSnapshot.empty),
      );
    });

    test('missing keys mean "no signal", and screen defaults to on', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(<Object?, Object?>{});
      expect(snapshot.battery, isNull);
      expect(snapshot.charging, isNull);
      expect(snapshot.screenOn, isTrue);
      expect(snapshot.sessions, isEmpty);
    });

    test('skips sessions with no package rather than dropping the payload', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [
            {'title': 'orphan', 'state': 3},
            _session(),
          ],
        ),
      );
      expect(snapshot.sessions, hasLength(1));
      expect(snapshot.sessions.single.packageName, 'com.spotify.music');
    });
  });

  group('idle derivation (screen state -> idle_seconds)', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000);

    test('screen on means idle 0 — the phone is in someone\'s hand', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(screenOn: true, screenOffSinceMillis: 500),
      );
      expect(snapshot.idleSeconds(now: now), 0);
    });

    test('screen off counts seconds since it went off', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          screenOn: false,
          screenOffSinceMillis: now.millisecondsSinceEpoch - 90 * 1000,
        ),
      );
      expect(snapshot.idleSeconds(now: now), 90);
    });

    test('crosses the 5-minute away boundary like the desktop path does', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          screenOn: false,
          screenOffSinceMillis: now.millisecondsSinceEpoch - 301 * 1000,
        ),
      );
      expect(snapshot.idleSeconds(now: now), greaterThan(300));
    });

    test('screen off with no known start reports null, not a fake zero', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(screenOn: false),
      );
      expect(snapshot.idleSeconds(now: now), isNull);
    });

    test('a clock that went backwards clamps to 0', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          screenOn: false,
          screenOffSinceMillis: now.millisecondsSinceEpoch + 5000,
        ),
      );
      expect(snapshot.idleSeconds(now: now), 0);
    });
  });

  group('media session -> NowPlaying', () {
    test('maps a playing session with full metadata', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session()]),
      );

      final nowPlaying = snapshot.nowPlaying()!;
      expect(nowPlaying.title, 'Marigold');
      expect(nowPlaying.artist, 'Periphery');
      expect(nowPlaying.album, 'Juggernaut');
      expect(nowPlaying.player, 'Spotify');
      expect(nowPlaying.state, NowPlayingState.playing);
      expect(nowPlaying.marqueeText, '♪ Marigold — Periphery');
    });

    test('STATE_PAUSED maps to paused', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session(state: 2)]),
      );
      expect(snapshot.nowPlaying()!.state, NowPlayingState.paused);
    });

    test('STATE_BUFFERING counts as playing', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session(state: 6)]),
      );
      expect(snapshot.nowPlaying()!.state, NowPlayingState.playing);
    });

    test('stopped / none / error states report nothing playing', () {
      for (final state in [0, 1, 7]) {
        final snapshot = AndroidPresenceSnapshot.fromChannel(
          _snapshot(sessions: [_session(state: state)]),
        );
        expect(snapshot.nowPlaying(), isNull, reason: 'state $state');
      }
    });

    test('a session with no title is skipped', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session(title: null)]),
      );
      expect(snapshot.nowPlaying(), isNull);
    });

    test('blank artist/album collapse to null rather than empty strings', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session(artist: '   ', album: '')]),
      );
      final nowPlaying = snapshot.nowPlaying()!;
      expect(nowPlaying.artist, isNull);
      expect(nowPlaying.album, isNull);
      expect(nowPlaying.marqueeText, '♪ Marigold');
    });

    test('a playing session beats a paused one regardless of order', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [
            _session(package: 'com.paused', title: 'Paused one', state: 2),
            _session(package: 'com.playing', title: 'Playing one', state: 3),
          ],
        ),
      );
      expect(snapshot.nowPlaying()!.title, 'Playing one');
    });

    test('falls back to the first paused session when nothing is playing', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [
            _session(package: 'com.first', title: 'First', state: 2),
            _session(package: 'com.second', title: 'Second', state: 2),
          ],
        ),
      );
      expect(snapshot.nowPlaying()!.title, 'First');
    });

    test('unmappable sessions do not hide a good one behind them', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [
            _session(package: 'com.dead', title: null, state: 1),
            _session(package: 'com.alive', title: 'Alive', state: 3),
          ],
        ),
      );
      expect(snapshot.nowPlaying()!.title, 'Alive');
    });
  });

  group('player naming', () {
    test('prefers the label PackageManager gave us', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [_session(package: 'com.spotify.music', label: 'Spotify')],
        ),
      );
      expect(snapshot.nowPlaying()!.player, 'Spotify');
    });

    test('falls back to the known-packages table when there is no label', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(
          sessions: [
            _session(package: 'com.google.android.apps.youtube.music', label: null),
          ],
        ),
      );
      expect(snapshot.nowPlaying()!.player, 'YouTube Music');
    });

    test('never surfaces a raw package id', () {
      expect(
        MediaSessionSnapshot.prettyPackageName('com.example.someplayer'),
        'Someplayer',
      );
      expect(MediaSessionSnapshot.prettyPackageName('vlc'), 'Vlc');
    });

    test('a whitespace-only label is treated as no label', () {
      final snapshot = AndroidPresenceSnapshot.fromChannel(
        _snapshot(sessions: [_session(package: 'org.videolan.vlc', label: '   ')]),
      );
      expect(snapshot.nowPlaying()!.player, 'VLC');
    });
  });

  group('toPresence', () {
    test('carries battery and charging through for the heartbeat', () {
      final now = DateTime.fromMillisecondsSinceEpoch(2000000);
      final presence = AndroidPresenceSnapshot.fromChannel(
        _snapshot(battery: 17, charging: false, sessions: [_session()]),
      ).toPresence(now: now);

      expect(presence.battery, 17);
      expect(presence.charging, isFalse);
      expect(presence.idleSeconds, 0);
      expect(presence.nowPlaying?.title, 'Marigold');
    });
  });
}
