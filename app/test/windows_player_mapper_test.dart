import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/presence/windows_player_mapper.dart';
import 'package:couples_app/domain/models/now_playing.dart';

void main() {
  group('WindowsPlayerMapper.map', () {
    test('maps a playing session with full fields', () {
      final result = WindowsPlayerMapper.map({
        'title': 'Marigold',
        'artist': 'yeule',
        'album': 'softscars',
        'player': 'Spotify.exe',
        'state': 'playing',
      });

      expect(result, isNotNull);
      expect(result!.title, 'Marigold');
      expect(result.artist, 'yeule');
      expect(result.album, 'softscars');
      expect(result.player, 'spotify');
      expect(result.state, NowPlayingState.playing);
      expect(result.marqueeText, '♪ Marigold — yeule');
    });

    test('maps a paused session with only a title', () {
      final result = WindowsPlayerMapper.map({
        'title': 'Sugar',
        'artist': null,
        'album': null,
        'player': null,
        'state': 'paused',
      });

      expect(result, isNotNull);
      expect(result!.state, NowPlayingState.paused);
      expect(result.artist, isNull);
      expect(result.player, isNull);
      expect(result.marqueeText, '♪ Sugar');
    });

    test('null result (no current session) maps to null', () {
      expect(WindowsPlayerMapper.map(null), isNull);
    });

    test('a non-map result maps to null', () {
      expect(WindowsPlayerMapper.map('unexpected'), isNull);
    });

    test('missing title maps to null', () {
      final result = WindowsPlayerMapper.map({
        'artist': 'yeule',
        'state': 'playing',
      });
      expect(result, isNull);
    });

    test('empty-string title maps to null', () {
      final result = WindowsPlayerMapper.map({'title': '', 'state': 'playing'});
      expect(result, isNull);
    });

    test('unknown/missing state maps to null', () {
      final result = WindowsPlayerMapper.map({
        'title': 'Something',
        'state': 'stopped',
      });
      expect(result, isNull);
    });

    test('a StandardMethodCodec-decoded Map<Object?, Object?> is accepted', () {
      // MethodChannel decodes a StandardMethodCodec map with dynamic key
      // and value types, not Map<String, dynamic> — make sure the mapper
      // doesn't assume a narrower map type than what actually arrives.
      final Map<Object?, Object?> raw = {
        'title': 'Video',
        'artist': 'Someone',
        'album': null,
        'player': 'msedge.exe',
        'state': 'playing',
      };
      final result = WindowsPlayerMapper.map(raw);
      expect(result, isNotNull);
      expect(result!.title, 'Video');
      expect(result.player, 'browser');
    });
  });

  group('WindowsPlayerMapper.prettifyPlayerId', () {
    test('null and empty stay null', () {
      expect(WindowsPlayerMapper.prettifyPlayerId(null), isNull);
      expect(WindowsPlayerMapper.prettifyPlayerId(''), isNull);
    });

    test('Spotify.exe -> spotify', () {
      expect(WindowsPlayerMapper.prettifyPlayerId('Spotify.exe'), 'spotify');
    });

    test('chrome/msedge/firefox all collapse to browser', () {
      expect(WindowsPlayerMapper.prettifyPlayerId('chrome.exe'), 'browser');
      expect(WindowsPlayerMapper.prettifyPlayerId('msedge.exe'), 'browser');
      expect(
        WindowsPlayerMapper.prettifyPlayerId(
          'Microsoft.MicrosoftEdge_8wekyb3d8bbwe!MicrosoftEdge',
        ),
        'browser',
      );
      expect(WindowsPlayerMapper.prettifyPlayerId('firefox.exe'), 'browser');
    });

    test('Apple Music AUMID -> apple music', () {
      expect(
        WindowsPlayerMapper.prettifyPlayerId(
          'AppleInc.AppleMusicWin_nzyj5cx40ttqa!App',
        ),
        'apple music',
      );
    });

    test('is case-insensitive', () {
      expect(WindowsPlayerMapper.prettifyPlayerId('SPOTIFY.EXE'), 'spotify');
    });

    test('unrecognized exe path falls back to a cleaned last segment', () {
      expect(
        WindowsPlayerMapper.prettifyPlayerId(
          r'C:\Program Files\VideoLAN\VLC\vlc.exe',
        ),
        'vlc',
      );
    });

    test('unrecognized packaged AUMID strips the !AppId suffix', () {
      expect(
        WindowsPlayerMapper.prettifyPlayerId('Some.Weird.App_abc123!App'),
        'some.weird.app_abc123',
      );
    });
  });
}
