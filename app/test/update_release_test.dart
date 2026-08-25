import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/updates/update_release.dart';

/// A trimmed-down copy of a real `releases/latest` response: the four
/// fields we read, the asset names we actually publish, and one extra
/// asset (`kehai-debug.apk`) that must never be picked.
const _latestJson = '''
{
  "tag_name": "v1.0.3",
  "name": "Kehai 1.0.3",
  "draft": false,
  "prerelease": false,
  "body": "OLED care, opaque Linux mini card.",
  "assets": [
    {
      "name": "kehai-debug.apk",
      "browser_download_url": "https://example.test/kehai-debug.apk",
      "size": 111
    },
    {
      "name": "kehai-release.apk",
      "browser_download_url": "https://example.test/kehai-release.apk",
      "size": 62914560
    },
    {
      "name": "kehai-windows-x64-1.0.3.zip",
      "browser_download_url": "https://example.test/kehai-windows-x64-1.0.3.zip",
      "size": 51200000
    },
    {
      "name": "kehai-linux-x64-1.0.3.tar.gz",
      "browser_download_url": "https://example.test/kehai-linux-x64-1.0.3.tar.gz",
      "size": 48000000
    }
  ]
}
''';

void main() {
  group('parseLatestRelease', () {
    test('reads the tag, the notes and every asset', () {
      final release = parseLatestRelease(_latestJson)!;

      expect(release.tag, 'v1.0.3');
      expect(release.version, '1.0.3');
      expect(release.notes, contains('OLED care'));
      expect(release.assets, hasLength(4));
      expect(release.assets.first.size, 111);
    });

    test('a body that is not a release answers null rather than throwing', () {
      // The three shapes GitHub actually hands back when something is
      // wrong: a 404 object, a rate-limit message, and truncated JSON.
      expect(parseLatestRelease('{"message":"Not Found"}'), isNull);
      expect(
        parseLatestRelease('{"message":"API rate limit exceeded"}'),
        isNull,
      );
      expect(parseLatestRelease('{"tag_name": "v1.0'), isNull);
      expect(parseLatestRelease(''), isNull);
      expect(parseLatestRelease('[]'), isNull);
    });

    test('an asset missing a url is skipped, not fatal', () {
      final release = parseLatestRelease('''
        {"tag_name":"v2.0.0","assets":[
          {"name":"kehai-release.apk"},
          {"name":"kehai-release.apk","browser_download_url":"u","size":5}
        ]}
      ''')!;

      expect(release.assets, hasLength(1));
      expect(release.assets.single.size, 5);
    });

    test('an asset with no size still parses — 0 means "do not check"', () {
      final release = parseLatestRelease(
        '{"tag_name":"v2.0.0","assets":[{"name":"a","browser_download_url":"u"}]}',
      )!;

      expect(release.assets.single.size, 0);
    });
  });

  group('normalizeVersion', () {
    test('strips the tag "v" and the build number', () {
      expect(normalizeVersion('v1.0.3'), '1.0.3');
      expect(normalizeVersion('V1.0.3'), '1.0.3');
      expect(normalizeVersion('1.0.2+3'), '1.0.2');
      expect(normalizeVersion('  v1.0.3  '), '1.0.3');
      expect(normalizeVersion('1.0.3'), '1.0.3');
    });
  });

  group('compareVersions', () {
    test('orders by numeric component, not by string', () {
      // The whole reason this isn't a string compare: "10" sorts before
      // "9" alphabetically.
      expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('a missing component is zero', () {
      expect(compareVersions('1.1', '1.1.0'), 0);
      expect(compareVersions('1.1', '1.1.1'), lessThan(0));
    });

    test('the tag "v" and the build number never change the answer', () {
      expect(compareVersions('v1.0.2', '1.0.2+3'), 0);
    });

    test('junk counts as zero rather than throwing', () {
      // A background check must not be able to crash on a mistyped tag.
      expect(compareVersions('1.x.3', '1.0.3'), 0);
      expect(compareVersions('nightly', '0.0.0'), 0);
    });
  });

  group('isNewerVersion', () {
    test('only strictly newer counts', () {
      expect(isNewerVersion('1.0.3', '1.0.2'), isTrue);
      expect(isNewerVersion('1.0.2', '1.0.2'), isFalse);
      expect(isNewerVersion('1.0.1', '1.0.2'), isFalse);
    });

    test('a debug version override makes everything newer', () {
      // The KEHAI_FAKE_VERSION path (see UpdateService): forcing the
      // current version down is what makes a live release testable.
      expect(isNewerVersion('1.0.2', '0.9.0'), isTrue);
    });
  });

  group('selectAsset', () {
    final assets = parseLatestRelease(_latestJson)!.assets;

    test('android takes the release apk and never the debug one', () {
      final asset = selectAsset(assets, UpdateTarget.android)!;
      expect(asset.name, 'kehai-release.apk');
    });

    test('windows takes the versioned zip', () {
      expect(
        selectAsset(assets, UpdateTarget.windows)!.name,
        'kehai-windows-x64-1.0.3.zip',
      );
    });

    test('linux takes the versioned tarball', () {
      expect(
        selectAsset(assets, UpdateTarget.linux)!.name,
        'kehai-linux-x64-1.0.3.tar.gz',
      );
    });

    test('a release without this platform\'s asset selects nothing', () {
      final apkOnly = parseLatestRelease('''
        {"tag_name":"v1.0.3","assets":[
          {"name":"kehai-release.apk","browser_download_url":"u","size":1}
        ]}
      ''')!;

      expect(selectAsset(apkOnly.assets, UpdateTarget.android), isNotNull);
      expect(selectAsset(apkOnly.assets, UpdateTarget.windows), isNull);
      expect(selectAsset(apkOnly.assets, UpdateTarget.linux), isNull);
    });

    test('a linux tarball is never mistaken for a windows zip', () {
      final linuxOnly = parseLatestRelease('''
        {"tag_name":"v1.0.3","assets":[
          {"name":"kehai-linux-x64-1.0.3.tar.gz","browser_download_url":"u","size":1}
        ]}
      ''')!;

      expect(selectAsset(linuxOnly.assets, UpdateTarget.windows), isNull);
    });
  });
}
