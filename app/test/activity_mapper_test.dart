import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/activity_mapper.dart';

void main() {
  group('ActivityMapper.mapWindowsExe', () {
    test('maps a coding tool', () {
      expect(ActivityMapper.mapWindowsExe('code'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapWindowsExe('idea64'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapWindowsExe('rider64'), 'coding ⌨\uFE0E');
    });

    test('maps creative tools', () {
      expect(ActivityMapper.mapWindowsExe('blender'), 'in Blender');
      expect(ActivityMapper.mapWindowsExe('krita'), 'drawing');
      expect(ActivityMapper.mapWindowsExe('photoshop'), 'drawing');
    });

    test('maps chat apps', () {
      expect(ActivityMapper.mapWindowsExe('discord'), 'chatting ✉');
    });

    test('maps game launchers/exes', () {
      expect(ActivityMapper.mapWindowsExe('steam'), 'gaming');
      expect(
        ActivityMapper.mapWindowsExe('valorant-win64-shipping'),
        'gaming',
      );
    });

    test('maps a streaming tool', () {
      expect(ActivityMapper.mapWindowsExe('obs64'), 'streaming ✧');
    });

    test('maps office writing tools', () {
      expect(ActivityMapper.mapWindowsExe('winword'), 'writing ✍\uFE0E');
    });

    test('maps browsers to the generic "browsing" label', () {
      for (final browser in ['chrome', 'msedge', 'firefox', 'brave']) {
        expect(ActivityMapper.mapWindowsExe(browser), 'browsing ☁\uFE0E');
      }
    });

    test('is case-insensitive', () {
      expect(ActivityMapper.mapWindowsExe('Code'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapWindowsExe('STEAM'), 'gaming');
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
        'gaming',
      );
    });

    test('maps browsers to the generic "browsing" label', () {
      expect(
        ActivityMapper.mapAndroidPackage('com.android.chrome'),
        'browsing ☁\uFE0E',
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

  group('ActivityMapper.mapLinuxClass', () {
    test('maps a coding tool', () {
      expect(ActivityMapper.mapLinuxClass('code'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapLinuxClass('codium'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapLinuxClass('jetbrains-idea-ce'), 'coding ⌨\uFE0E');
    });

    test('maps creative tools', () {
      expect(ActivityMapper.mapLinuxClass('blender'), 'in Blender');
      expect(ActivityMapper.mapLinuxClass('krita'), 'drawing');
      expect(ActivityMapper.mapLinuxClass('gimp'), 'drawing');
    });

    test('maps chat apps', () {
      expect(ActivityMapper.mapLinuxClass('discord'), 'chatting ✉');
      expect(ActivityMapper.mapLinuxClass('discordcanary'), 'chatting ✉');
    });

    test('maps game launchers', () {
      expect(ActivityMapper.mapLinuxClass('steam'), 'gaming');
      expect(ActivityMapper.mapLinuxClass('heroic'), 'gaming');
    });

    test('maps a streaming tool', () {
      expect(ActivityMapper.mapLinuxClass('obs'), 'streaming ✧');
    });

    test('maps browsers to the generic "browsing" label', () {
      for (final browser in [
        'firefox',
        'chromium',
        'google-chrome',
        'brave-browser',
      ]) {
        expect(ActivityMapper.mapLinuxClass(browser), 'browsing ☁\uFE0E');
      }
    });

    test('is case-insensitive', () {
      expect(ActivityMapper.mapLinuxClass('Code'), 'coding ⌨\uFE0E');
      expect(ActivityMapper.mapLinuxClass('Firefox'), 'browsing ☁\uFE0E');
      expect(ActivityMapper.mapLinuxClass('STEAM'), 'gaming');
    });

    test('spotify is deliberately unmapped — now_playing covers it better', () {
      expect(ActivityMapper.mapLinuxClass('spotify'), isNull);
      expect(
        ActivityMapper.mapLinuxClass('spotify', shareUnknown: true),
        isNotNull,
      );
    });

    test('an unrecognized class returns null by default', () {
      expect(ActivityMapper.mapLinuxClass('org.kde.somenewapp'), isNull);
    });

    test('shareUnknown returns a cleaned, title-cased guess instead', () {
      expect(
        ActivityMapper.mapLinuxClass('some_random-tool', shareUnknown: true),
        'Some Random Tool',
      );
    });

    test('null/empty input is always null, even with shareUnknown', () {
      expect(ActivityMapper.mapLinuxClass(null), isNull);
      expect(ActivityMapper.mapLinuxClass(null, shareUnknown: true), isNull);
      expect(ActivityMapper.mapLinuxClass('', shareUnknown: true), isNull);
    });
  });

  group('ActivityMapper.refineBrowserLabel', () {
    test('refines to "watching YouTube" on a hyphen-suffixed title', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Never Gonna Give You Up - YouTube',
        ),
        'watching YouTube',
      );
    });

    test('refines YouTube titles with en dash and em dash separators', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Never Gonna Give You Up – YouTube', // en dash
        ),
        'watching YouTube',
      );
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Never Gonna Give You Up — YouTube', // em dash
        ),
        'watching YouTube',
      );
    });

    test('refines Polish-locale YouTube titles (em dash is standard there)', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Najlepsze przeboje 2026 — YouTube',
        ),
        'watching YouTube',
      );
    });

    test('refines YouTube titles regardless of surrounding whitespace/case', () {
      expect(
        ActivityMapper.refineBrowserLabel('browsing ☁\uFE0E', 'Some video -youtube'),
        'watching YouTube',
      );
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Some video -  YouTube  ',
        ),
        'watching YouTube',
      );
    });

    test('refines to "watching Netflix" when the title contains Netflix', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Stranger Things - Netflix',
        ),
        'watching Netflix',
      );
    });

    test('refines to "watching Twitch" when the title contains Twitch', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'CoolStreamer - Twitch',
        ),
        'watching Twitch',
      );
    });

    test('refines to "writing ✍\uFE0E" on a Google Docs suffixed title', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Our Anniversary Plans - Google Docs',
        ),
        'writing ✍\uFE0E',
      );
      // en dash variant, as some locales render it.
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Our Anniversary Plans – Google Docs',
        ),
        'writing ✍\uFE0E',
      );
    });

    test('refines to "coding ⌨\uFE0E" when the title contains GitHub', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'kehai/couples-app: pull request #42 - GitHub',
        ),
        'coding ⌨\uFE0E',
      );
    });

    test('refines to "scrolling Reddit" when the title contains Reddit', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'r/aww - Reddit',
        ),
        'scrolling Reddit',
      );
    });

    test('refines to "reading" when the title contains Wikipedia', () {
      expect(
        ActivityMapper.refineBrowserLabel(
          'browsing ☁\uFE0E',
          'Long-distance relationship - Wikipedia',
        ),
        'reading',
      );
    });

    test('never returns the raw title itself for an unmatched pattern', () {
      final result = ActivityMapper.refineBrowserLabel(
        'browsing ☁\uFE0E',
        'my secret search query - Google Search',
      );
      expect(result, 'browsing ☁\uFE0E');
      expect(result, isNot(contains('secret search query')));
    });

    test('is a no-op on labels other than the generic "browsing" one', () {
      expect(
        ActivityMapper.refineBrowserLabel('in Blender', 'Untitled - YouTube'),
        'in Blender',
        reason:
            'refinement only ever touches the generic browser label, never '
            'a specifically-mapped app',
      );
      expect(ActivityMapper.refineBrowserLabel('gaming', null), 'gaming');
    });

    test('null/empty/blank title leaves the label untouched', () {
      expect(ActivityMapper.refineBrowserLabel('browsing ☁\uFE0E', null), 'browsing ☁\uFE0E');
      expect(ActivityMapper.refineBrowserLabel('browsing ☁\uFE0E', ''), 'browsing ☁\uFE0E');
      expect(
        ActivityMapper.refineBrowserLabel('browsing ☁\uFE0E', '   '),
        'browsing ☁\uFE0E',
      );
    });

    test('null label stays null', () {
      expect(ActivityMapper.refineBrowserLabel(null, ' - YouTube'), isNull);
    });

    test('a title with no known pattern leaves the generic label alone', () {
      expect(
        ActivityMapper.refineBrowserLabel('browsing ☁\uFE0E', 'New Tab'),
        'browsing ☁\uFE0E',
      );
    });
  });
}
