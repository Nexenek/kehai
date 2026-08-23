import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/presence/mpris_mapper.dart';
import 'package:couples_app/domain/models/now_playing.dart';

/// Builds the `Map<String, DBusValue>` shape [MprisMapper.map] expects —
/// i.e. what `DBusDict.asStringVariantDict()` returns for a player's
/// `Metadata` property once its outer `a{sv}` variant layer is unwrapped.
/// No D-Bus connection involved: these are plain in-memory value objects.
Map<String, DBusValue> _metadata({
  String? title,
  List<String>? artists,
  String? album,
}) {
  return {
    if (title != null) 'xesam:title': DBusString(title),
    if (artists != null) 'xesam:artist': DBusArray.string(artists),
    if (album != null) 'xesam:album': DBusString(album),
  };
}

void main() {
  group('MprisMapper.map', () {
    test('maps a Playing player with full metadata', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.spotify',
        playbackStatus: 'Playing',
        metadata: _metadata(
          title: 'Marigold',
          artists: ['yeule'],
          album: 'softscars',
        ),
      );

      expect(result, isNotNull);
      expect(result!.title, 'Marigold');
      expect(result.artist, 'yeule');
      expect(result.album, 'softscars');
      expect(result.player, 'spotify');
      expect(result.state, NowPlayingState.playing);
      expect(result.marqueeText, '♪ Marigold — yeule');
    });

    test('maps a Paused player', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.vlc',
        playbackStatus: 'Paused',
        metadata: _metadata(title: 'Sugar'),
      );

      expect(result, isNotNull);
      expect(result!.state, NowPlayingState.paused);
      expect(result.artist, isNull);
      expect(result.marqueeText, '♪ Sugar');
    });

    test('Stopped status maps to null regardless of metadata', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.rhythmbox',
        playbackStatus: 'Stopped',
        metadata: _metadata(title: 'Something'),
      );
      expect(result, isNull);
    });

    test('unknown/missing status maps to null', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.foo',
        playbackStatus: null,
        metadata: _metadata(title: 'Something'),
      );
      expect(result, isNull);
    });

    test(
      'Playing with no title (empty metadata dict between tracks) maps to null',
      () {
        final result = MprisMapper.map(
          busName: 'org.mpris.MediaPlayer2.spotify',
          playbackStatus: 'Playing',
          metadata: const {},
        );
        expect(result, isNull);
      },
    );

    test('empty-string title also maps to null', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.spotify',
        playbackStatus: 'Playing',
        metadata: _metadata(title: ''),
      );
      expect(result, isNull);
    });

    test('takes the first non-empty artist from a multi-artist array', () {
      final result = MprisMapper.map(
        busName: 'org.mpris.MediaPlayer2.spotify',
        playbackStatus: 'Playing',
        metadata: _metadata(
          title: 'Collab',
          artists: ['', 'Real Artist', 'Feature'],
        ),
      );
      expect(result!.artist, 'Real Artist');
    });

    test(
      'strips the Chromium-style .instanceNNNN suffix from the player label',
      () {
        final result = MprisMapper.map(
          busName: 'org.mpris.MediaPlayer2.chromium.instance1234',
          playbackStatus: 'Playing',
          metadata: _metadata(title: 'Video'),
        );
        expect(result!.player, 'chromium');
      },
    );

    test(
      'a busName with no MPRIS prefix is used as-is for the player label',
      () {
        final result = MprisMapper.map(
          busName: 'com.example.SomeWeirdPlayer',
          playbackStatus: 'Playing',
          metadata: _metadata(title: 'Video'),
        );
        expect(result!.player, 'com.example.SomeWeirdPlayer');
      },
    );

    test(
      'a wrong-typed title value (not DBusString) is treated as missing',
      () {
        final result = MprisMapper.map(
          busName: 'org.mpris.MediaPlayer2.weird',
          playbackStatus: 'Playing',
          metadata: {'xesam:title': DBusUint32(42)},
        );
        expect(result, isNull);
      },
    );
  });
}
