import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/presence/linux_foreground_app_detector.dart';

/// Builds a fake successful [ProcessResult] carrying [stdout].
ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');

ProcessResult _fail({int exitCode = 1, String stderr = 'error'}) =>
    ProcessResult(0, exitCode, '', stderr);

void main() {
  group('LinuxForegroundAppParsers.parseHyprctlActiveWindow', () {
    test('parses a well-formed hyprctl activewindow -j result', () {
      final json = jsonEncode({
        'address': '0xdeadbeef',
        'mapped': true,
        'class': 'firefox',
        'title': 'Kehai — YouTube',
        'initialClass': 'firefox',
        'initialTitle': 'New Tab',
        'pid': 1234,
      });

      final result = LinuxForegroundAppParsers.parseHyprctlActiveWindow(json);

      expect(result, isNotNull);
      expect(result!.wmClass, 'firefox');
      expect(result.title, 'Kehai — YouTube');
    });

    test('an empty object (nothing focused) maps to null', () {
      expect(LinuxForegroundAppParsers.parseHyprctlActiveWindow('{}'), isNull);
    });

    test('missing class maps to null', () {
      final json = jsonEncode({'title': 'Untitled'});
      expect(LinuxForegroundAppParsers.parseHyprctlActiveWindow(json), isNull);
    });

    test('empty-string class maps to null', () {
      final json = jsonEncode({'class': '', 'title': 'Untitled'});
      expect(LinuxForegroundAppParsers.parseHyprctlActiveWindow(json), isNull);
    });

    test('missing title is treated as empty, not a null result', () {
      final json = jsonEncode({'class': 'kitty'});
      final result = LinuxForegroundAppParsers.parseHyprctlActiveWindow(json);
      expect(result, isNotNull);
      expect(result!.title, '');
    });

    test('non-JSON / garbage output maps to null, never throws', () {
      expect(
        LinuxForegroundAppParsers.parseHyprctlActiveWindow('not json at all'),
        isNull,
      );
      expect(LinuxForegroundAppParsers.parseHyprctlActiveWindow(''), isNull);
    });

    test('a JSON array (unexpected shape) maps to null', () {
      expect(
        LinuxForegroundAppParsers.parseHyprctlActiveWindow('[]'),
        isNull,
      );
    });
  });

  group('LinuxForegroundAppParsers.parseSwayTree', () {
    test('finds the focused leaf node (native Wayland client, app_id)', () {
      final tree = {
        'type': 'root',
        'focused': false,
        'nodes': [
          {
            'type': 'output',
            'focused': false,
            'nodes': [
              {
                'type': 'workspace',
                'focused': false,
                'nodes': [
                  {
                    'type': 'con',
                    'focused': false,
                    'app_id': 'kitty',
                    'name': 'not this one',
                  },
                  {
                    'type': 'con',
                    'focused': true,
                    'app_id': 'firefox',
                    'name': 'Kehai — YouTube',
                    'window_properties': null,
                  },
                ],
                'floating_nodes': <Object?>[],
              },
            ],
          },
        ],
      };

      final result = LinuxForegroundAppParsers.parseSwayTree(
        jsonEncode(tree),
      );

      expect(result, isNotNull);
      expect(result!.wmClass, 'firefox');
      expect(result.title, 'Kehai — YouTube');
    });

    test('falls back to window_properties.class for an XWayland client', () {
      final tree = {
        'type': 'root',
        'focused': false,
        'nodes': <Object?>[],
        'floating_nodes': [
          {
            'type': 'con',
            'focused': true,
            'app_id': null,
            'name': 'Blender',
            'window_properties': {'class': 'Blender', 'instance': 'blender'},
          },
        ],
      };

      final result = LinuxForegroundAppParsers.parseSwayTree(
        jsonEncode(tree),
      );

      expect(result, isNotNull);
      expect(result!.wmClass, 'Blender');
      expect(result.title, 'Blender');
    });

    test('searches nested floating_nodes as well as nodes', () {
      final tree = {
        'type': 'root',
        'focused': false,
        'nodes': [
          {
            'type': 'workspace',
            'focused': false,
            'nodes': <Object?>[],
            'floating_nodes': [
              {
                'type': 'con',
                'focused': true,
                'app_id': 'discord',
                'name': 'Discord',
              },
            ],
          },
        ],
      };

      final result = LinuxForegroundAppParsers.parseSwayTree(
        jsonEncode(tree),
      );

      expect(result, isNotNull);
      expect(result!.wmClass, 'discord');
    });

    test('no focused node anywhere in the tree maps to null', () {
      final tree = {
        'type': 'root',
        'focused': false,
        'nodes': [
          {'type': 'con', 'focused': false, 'app_id': 'kitty'},
        ],
      };

      expect(
        LinuxForegroundAppParsers.parseSwayTree(jsonEncode(tree)),
        isNull,
      );
    });

    test('a focused node with neither app_id nor window_properties.class '
        'maps to null', () {
      final tree = {
        'type': 'root',
        'focused': true,
        'name': 'root has no app_id, this is a degenerate case',
      };

      expect(
        LinuxForegroundAppParsers.parseSwayTree(jsonEncode(tree)),
        isNull,
      );
    });

    test('non-JSON / garbage output maps to null, never throws', () {
      expect(LinuxForegroundAppParsers.parseSwayTree('not json'), isNull);
      expect(LinuxForegroundAppParsers.parseSwayTree(''), isNull);
    });
  });

  group('LinuxForegroundAppDetector.detect', () {
    test('Hyprland: guarded by HYPRLAND_INSTANCE_SIGNATURE, calls hyprctl', () async {
      final calls = <List<String>>[];
      final detector = LinuxForegroundAppDetector(
        environment: const {'HYPRLAND_INSTANCE_SIGNATURE': 'abc123'},
        processRunner: (exe, args) async {
          calls.add([exe, ...args]);
          return _ok(jsonEncode({'class': 'code', 'title': 'main.dart'}));
        },
      );

      final result = await detector.detect();

      expect(result, isNotNull);
      expect(result!.wmClass, 'code');
      expect(calls, [
        ['hyprctl', 'activewindow', '-j'],
      ]);
    });

    test(
      'Hyprland: does not fall through to Sway/X11 even when nothing is '
      'focused this poll',
      () async {
        var swayCalled = false;
        final detector = LinuxForegroundAppDetector(
          environment: const {
            'HYPRLAND_INSTANCE_SIGNATURE': 'abc123',
            'SWAYSOCK': '/tmp/sway.sock', // should never be consulted
          },
          processRunner: (exe, args) async {
            if (exe == 'swaymsg') swayCalled = true;
            if (exe == 'hyprctl') return _ok('{}'); // nothing focused
            return _fail();
          },
        );

        final result = await detector.detect();

        expect(result, isNull);
        expect(swayCalled, isFalse);
      },
    );

    test(
      'Hyprland: a failed spawn (hyprctl missing) is cached and never '
      'retried, falling through to Sway on subsequent polls',
      () async {
        var hyprCalls = 0;
        var swayCalls = 0;
        final detector = LinuxForegroundAppDetector(
          environment: const {
            'HYPRLAND_INSTANCE_SIGNATURE': 'abc123',
            'SWAYSOCK': '/tmp/sway.sock',
          },
          processRunner: (exe, args) async {
            if (exe == 'hyprctl') {
              hyprCalls++;
              throw ProcessException('hyprctl', args, 'not found');
            }
            if (exe == 'swaymsg') {
              swayCalls++;
              return _ok(
                jsonEncode({'focused': true, 'app_id': 'firefox', 'name': ''}),
              );
            }
            return _fail();
          },
        );

        final first = await detector.detect();
        expect(first, isNull);
        expect(hyprCalls, 1);
        expect(swayCalls, 0, reason: 'first poll should still only try Hyprland');

        final second = await detector.detect();
        expect(second, isNotNull);
        expect(second!.wmClass, 'firefox');
        expect(hyprCalls, 1, reason: 'hyprctl must not be spawned again');
        expect(swayCalls, 1);
      },
    );

    test('Sway: guarded by SWAYSOCK when Hyprland is not present', () async {
      final calls = <List<String>>[];
      final detector = LinuxForegroundAppDetector(
        environment: const {'SWAYSOCK': '/run/user/1000/sway-ipc.sock'},
        processRunner: (exe, args) async {
          calls.add([exe, ...args]);
          return _ok(
            jsonEncode({
              'focused': false,
              'nodes': [
                {'focused': true, 'app_id': 'chromium', 'name': 'Reddit'},
              ],
            }),
          );
        },
      );

      final result = await detector.detect();

      expect(result, isNotNull);
      expect(result!.wmClass, 'chromium');
      expect(calls, [
        ['swaymsg', '-t', 'get_tree'],
      ]);
    });

    test('X11: only reached when neither Wayland env var is set', () async {
      final calls = <List<String>>[];
      final detector = LinuxForegroundAppDetector(
        environment: const {'DISPLAY': ':0'},
        processRunner: (exe, args) async {
          calls.add([exe, ...args]);
          if (args.contains('getwindowclassname')) return _ok('firefox\n');
          if (args.contains('getwindowname')) {
            return _ok('Kehai — YouTube\n');
          }
          return _fail();
        },
      );

      final result = await detector.detect();

      expect(result, isNotNull);
      expect(result!.wmClass, 'firefox');
      expect(result.title, 'Kehai — YouTube');
      expect(calls.length, 2);
    });

    test('X11: a failed xdotool spawn is cached and never retried', () async {
      var xdotoolCalls = 0;
      final detector = LinuxForegroundAppDetector(
        environment: const {'DISPLAY': ':0'},
        processRunner: (exe, args) async {
          xdotoolCalls++;
          throw ProcessException('xdotool', args, 'not found');
        },
      );

      final first = await detector.detect();
      final second = await detector.detect();

      expect(first, isNull);
      expect(second, isNull);
      expect(xdotoolCalls, 1, reason: 'xdotool existence check happens once');
    });

    test('no env var set at all (e.g. GNOME Wayland) maps to null, no '
        'process spawned', () async {
      var called = false;
      final detector = LinuxForegroundAppDetector(
        environment: const {},
        processRunner: (exe, args) async {
          called = true;
          return _fail();
        },
      );

      final result = await detector.detect();

      expect(result, isNull);
      expect(called, isFalse);
    });
  });
}
