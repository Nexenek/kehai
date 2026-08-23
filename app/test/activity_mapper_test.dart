import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/activity_mapper.dart';

void main() {
  group('ActivityMapper.mapWindowsExe', () {
    test('maps a coding tool', () {
      expect(ActivityMapper.mapWindowsExe('code'), 'coding ⌨');
      expect(ActivityMapper.mapWindowsExe('idea64'), 'coding ⌨');
      expect(ActivityMapper.mapWindowsExe('rider64'), 'coding ⌨');
    });

    test('maps creative tools', () {
      expect(ActivityMapper.mapWindowsExe('blender'), 'in Blender 🎨');
      expect(ActivityMapper.mapWindowsExe('krita'), 'drawing 🎨');
      expect(ActivityMapper.mapWindowsExe('photoshop'), 'drawing 🎨');
    });

    test('maps chat apps', () {
      expect(ActivityMapper.mapWindowsExe('discord'), 'chatting ✉');
    });

    test('maps game launchers/exes', () {
      expect(ActivityMapper.mapWindowsExe('steam'), 'gaming 🎮');
      expect(
        ActivityMapper.mapWindowsExe('valorant-win64-shipping'),
        'gaming 🎮',
      );
    });

    test('maps a streaming tool', () {
      expect(ActivityMapper.mapWindowsExe('obs64'), 'streaming ✧');
    });

    test('maps office writing tools', () {
      expect(ActivityMapper.mapWindowsExe('winword'), 'writing ✍');
    });

    test('maps browsers to the generic "browsing" label', () {
      for (final browser in ['chrome', 'msedge', 'firefox', 'brave']) {
        expect(ActivityMapper.mapWindowsExe(browser), 'browsing ☁');
      }
    });

    test('is case-insensitive', () {
      expect(ActivityMapper.mapWindowsExe('Code'), 'coding ⌨');
      expect(ActivityMapper.mapWindowsExe('STEAM'), 'gaming 🎮');
    });

    test('spotify is deliberately unmapped — now_playing covers it better', () {
      expect(ActivityMapper.mapWindowsExe('spotify'), isNull);
      expect(
        ActivityMapper.mapWindowsExe('spotify', shareUnknown: true),
        isNotNull,
        reason:
            'shareUnknown is a separate opt-in and still applies — spotify '
            'just has no table entry, it is not specially blocked',
      );
    });

    test('an unrecognized exe returns null by default', () {
      expect(ActivityMapper.mapWindowsExe('some_random_tool'), isNull);
    });

    test('shareUnknown returns a cleaned, title-cased guess instead', () {
      expect(
        ActivityMapper.mapWindowsExe('some_random-tool', shareUnknown: true),
        'Some Random Tool',
      );
    });

    test('null/empty input is always null, even with shareUnknown', () {
      expect(ActivityMapper.mapWindowsExe(null), isNull);
      expect(ActivityMapper.mapWindowsExe(null, shareUnknown: true), isNull);
      expect(ActivityMapper.mapWindowsExe('', shareUnknown: true), isNull);
    });
  });

  group('ActivityMapper.mapAndroidPackage', () {
    test('maps short-video/social apps', () {
      expect(
        ActivityMapper.mapAndroidPackage('com.ss.android.ugc.trill'),
        'scrolling TikTok',
      );
      expect(
        ActivityMapper.mapAndroidPackage('com.zhiliaoapp.musically'),
        'scrolling TikTok',
      );
      expect(
        ActivityMapper.mapAndroidPackage('com.instagram.android'),
        'on Instagram',
      );
    });

    test('maps YouTube to "watching", distinct from now-playing', () {
      expect(
        ActivityMapper.mapAndroidPackage('com.google.android.youtube'),
        'watching YouTube',
      );
    });

    test('maps chat apps', () {
      expect(ActivityMapper.mapAndroidPackage('com.whatsapp'), 'chatting ✉');
    });

    test('maps game packages', () {
      expect(
        ActivityMapper.mapAndroidPackage('com.roblox.client'),
        'gaming 🎮',
      );
    });

    test('maps browsers to the generic "browsing" label', () {
      expect(
        ActivityMapper.mapAndroidPackage('com.android.chrome'),
        'browsing ☁',
      );
    });

    test('is case-insensitive', () {
      expect(
        ActivityMapper.mapAndroidPackage('COM.INSTAGRAM.ANDROID'),
        'on Instagram',
      );
    });

    test(
      'music packages (Spotify, YouTube Music) are deliberately unmapped',
      () {
        expect(ActivityMapper.mapAndroidPackage('com.spotify.music'), isNull);
        expect(
          ActivityMapper.mapAndroidPackage(
            'com.google.android.apps.youtube.music',
          ),
          isNull,
        );
      },
    );

    test('an unrecognized package returns null by default', () {
      expect(ActivityMapper.mapAndroidPackage('com.some.unknown.app'), isNull);
    });

    test(
      'shareUnknown title-cases the last package segment, not the whole id',
      () {
        expect(
          ActivityMapper.mapAndroidPackage(
            'com.some.cool_app',
            shareUnknown: true,
          ),
          'Cool App',
        );
      },
    );

    test('null/empty input is always null, even with shareUnknown', () {
      expect(ActivityMapper.mapAndroidPackage(null), isNull);
      expect(
        ActivityMapper.mapAndroidPackage(null, shareUnknown: true),
        isNull,
      );
      expect(ActivityMapper.mapAndroidPackage('', shareUnknown: true), isNull);
    });
  });
}
