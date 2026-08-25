import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/updates/update_scripts.dart';

/// The helper scripts are the one part of an update that runs *after* the
/// app is gone — nothing can catch a mistake in them at runtime, and a bad
/// one costs the user their install. So the ordering rules the design
/// depends on are asserted here at the string level: wait first, swap
/// second, relaunch third, and every path quoted.
void main() {
  const pid = 4242;

  group('the windows helper', () {
    final script = windowsUpdateScript(
      pid: pid,
      stagingDir: r'C:\Users\a b\AppData\Local\Temp\kehai_update_x\extracted',
      installDir: r'C:\Users\a b\Kehai',
      exePath: r'C:\Users\a b\Kehai\couples_app.exe',
    );

    test('carries the absolute paths it was given, quoted', () {
      expect(script, contains(r'set "INSTALL=C:\Users\a b\Kehai"'));
      expect(script, contains(r'set "EXE=C:\Users\a b\Kehai\couples_app.exe"'));
      expect(script, contains('set "PID=$pid"'));
      // Every use is quoted too — the install dir has a space in it.
      expect(script, contains('robocopy "%STAGING%" "%INSTALL%"'));
      expect(script, contains('start "" "%EXE%"'));
    });

    test('waits for our PID before it touches the install dir', () {
      expect(
        script.indexOf('tasklist'),
        lessThan(script.indexOf('robocopy')),
        reason: 'copying over a running install is how you get a broken one',
      );
    });

    test('relaunches only after the copy, and only if it worked', () {
      expect(script.indexOf('robocopy'), lessThan(script.indexOf('start ""')));
      // robocopy's 0-7 are success; 8+ jumps past the relaunch.
      expect(script, contains('if errorlevel 8 goto done'));
    });

    test('never mirrors — /MIR would delete whatever lives beside the app', () {
      expect(script, isNot(contains('/MIR')));
      expect(script, contains('/E'));
    });

    test('waits with ping, not timeout — a detached helper has no console', () {
      expect(script, contains('ping -n 2 127.0.0.1'));
      expect(script, isNot(contains('timeout /t')));
    });

    test('deletes the staging dir and then itself', () {
      expect(script, contains('rmdir /s /q "%STAGING%"'));
      expect(script.trimRight(), endsWith(r'del "%~f0"'));
    });
  });

  group('the linux helper', () {
    const install = '/home/a b/.local/opt/kehai';
    final script = linuxUpdateScript(
      pid: pid,
      stagingDir: '/tmp/kehai_update_x/extracted/kehai-linux-x64-1.0.3/bundle',
      installDir: install,
      exePath: '$install/couples_app',
    );

    test('carries the absolute paths it was given, quoted', () {
      expect(script, contains('INSTALL="$install"'));
      expect(script, contains('EXE="$install/couples_app"'));
      expect(
        script,
        contains(
          'STAGING="/tmp/kehai_update_x/extracted/kehai-linux-x64-1.0.3/bundle"',
        ),
      );
      expect(script, contains('PID=$pid'));
    });

    test('the backup is the install dir with .old, beside it', () {
      expect(backupDirPath(install), '$install.old');
      expect(script, contains('BACKUP="$install.old"'));
    });

    test('waits for our PID before the swap, and gives up rather than '
        'swapping under a live process', () {
      expect(
        script.indexOf(r'kill -0 "$PID"'),
        lessThan(script.indexOf(r'mv "$INSTALL"')),
      );
      expect(script, contains('exit 1'));
    });

    test('the swap is old-aside-then-new-into-place, in that order', () {
      final aside = script.indexOf(r'mv "$INSTALL" "$BACKUP"');
      final into = script.indexOf(r'mv "$STAGING" "$INSTALL"');
      expect(aside, greaterThan(0));
      expect(into, greaterThan(aside));
    });

    test('a failed second move puts the working copy back', () {
      expect(script, contains(r'mv "$BACKUP" "$INSTALL"'));
    });

    test('relaunches detached, after the swap', () {
      final into = script.indexOf(r'mv "$STAGING" "$INSTALL"');
      final launch = script.indexOf(r'nohup "$EXE"');
      expect(launch, greaterThan(into));
      expect(script, contains('&'));
    });

    test('leaves the directory it is about to move', () {
      expect(script, contains('cd /'));
    });

    test('deletes itself on every path out', () {
      // Four exits: gave up waiting, first mv failed, second mv failed, and
      // the happy one.
      expect(r'rm -f "$0"'.allMatches(script).length, greaterThan(0));
      expect(script.trimRight(), endsWith(r'rm -f "$0"'));
    });
  });
}
