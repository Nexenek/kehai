import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ambient_line.dart';
import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';

DeviceStatus _device({
  String kind = 'desktop',
  Duration sinceLastSeen = Duration.zero,
  NowPlaying? nowPlaying,
  int? idleSeconds,
  String? activity,
  double? battery,
  bool? charging,
}) {
  return DeviceStatus(
    id: '$kind-${sinceLastSeen.inSeconds}-${identityHashCode(nowPlaying)}',
    ownerId: 'partner',
    name: 'test device',
    kind: kind,
    lastSeen: DateTime.now().toUtc().subtract(sinceLastSeen),
    nowPlaying: nowPlaying,
    idleSeconds: idleSeconds,
    activity: activity,
    battery: battery,
    charging: charging,
  );
}

const _playing = NowPlaying(
  title: 'Marigold',
  artist: 'yeule',
  state: NowPlayingState.playing,
);
const _paused = NowPlaying(
  title: 'Sugar',
  artist: 'System',
  state: NowPlayingState.paused,
);

void main() {
  group('resolveAmbientLine precedence', () {
    test('no devices at all -> null (offline)', () {
      expect(resolveAmbientLine(const []), isNull);
    });

    test('all devices offline -> null, even with a stale now_playing', () {
      final devices = [
        _device(sinceLastSeen: const Duration(hours: 1), nowPlaying: _playing),
      ];
      expect(resolveAmbientLine(devices), isNull);
    });

    test('now_playing beats everything else', () {
      final devices = [
        _device(
          kind: 'desktop',
          nowPlaying: _playing,
          activity: 'gaming',
          idleSeconds: 0,
        ),
      ];
      final line = resolveAmbientLine(devices);
      expect(line, isNotNull);
      expect(line!.kind, AmbientLineKind.nowPlaying);
      expect(line.text, '♪ Marigold — yeule');
    });

    test('now_playing with no artist omits the dash', () {
      const track = NowPlaying(
        title: 'Solo Track',
        state: NowPlayingState.playing,
      );
      final line = resolveAmbientLine([_device(nowPlaying: track)]);
      expect(line!.text, '♪ Solo Track');
    });

    test('a Playing player on one device beats a Paused player on another', () {
      final devices = [
        _device(kind: 'desktop', nowPlaying: _paused),
        _device(kind: 'desktop', nowPlaying: _playing),
      ];
      final line = resolveAmbientLine(devices);
      expect(line!.text, contains('Marigold'));
    });

    test(
      'Paused now_playing is ignored — lingering paused sessions must not '
      'read as listening (falls through to activity)',
      () {
        final devices = [_device(nowPlaying: _paused, activity: 'gaming')];
        final line = resolveAmbientLine(devices);
        expect(line!.kind, AmbientLineKind.activity);
        expect(line.text, 'gaming');
      },
    );

    test(
      'Paused now_playing with nothing else falls through to presence',
      () {
        final devices = [
          _device(kind: 'phone', nowPlaying: _paused, idleSeconds: 10),
        ];
        final line = resolveAmbientLine(devices);
        expect(line!.kind, AmbientLineKind.onPhone);
      },
    );

    test('activity beats presence/away when no now_playing', () {
      final devices = [_device(activity: 'gaming', idleSeconds: 400)];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.activity);
      expect(line.text, 'gaming');
    });

    test('online desktop, low idle -> "at their computer"', () {
      final devices = [_device(kind: 'desktop', idleSeconds: 30)];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.atComputer);
      expect(line.text, AppStrings.ambientAtComputer);
    });

    test('online phone, low idle -> "on their phone"', () {
      final devices = [_device(kind: 'phone', idleSeconds: 30)];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.onPhone);
      expect(line.text, AppStrings.ambientOnPhone);
    });

    test('online with no idle signal at all defaults to present, not away', () {
      final devices = [_device(kind: 'desktop', idleSeconds: null)];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.atComputer);
    });

    test('idle >= 5 minutes on every online device -> away', () {
      final devices = [_device(kind: 'desktop', idleSeconds: 301)];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.away);
      expect(line.text, AppStrings.ambientAway);
    });

    test(
      'idle exactly at the 5-minute boundary counts as away, not present',
      () {
        final devices = [_device(idleSeconds: 300)];
        final line = resolveAmbientLine(devices);
        expect(line!.kind, AmbientLineKind.away);
      },
    );

    test('two online devices: the freshest (lowest idle) wins over away', () {
      final devices = [
        _device(kind: 'desktop', idleSeconds: 600), // away on its own
        _device(kind: 'phone', idleSeconds: 10), // active
      ];
      final line = resolveAmbientLine(devices);
      expect(line!.kind, AmbientLineKind.onPhone);
    });
  });

  group('resolvePhoneBattery precedence', () {
    test('no phone device with a battery reading -> none', () {
      final devices = [_device(kind: 'desktop', battery: 5)];
      expect(resolvePhoneBattery(devices).kind, BatteryGlyphKind.none);
    });

    test('phone battery above threshold and not charging -> none', () {
      final devices = [_device(kind: 'phone', battery: 55, charging: false)];
      expect(resolvePhoneBattery(devices).kind, BatteryGlyphKind.none);
    });

    test('phone battery at or below 20 and not charging -> low', () {
      final devices = [_device(kind: 'phone', battery: 20, charging: false)];
      final info = resolvePhoneBattery(devices);
      expect(info.kind, BatteryGlyphKind.low);
      expect(info.tooltip, contains('20%'));
    });

    test('charging takes priority over a low reading', () {
      final devices = [_device(kind: 'phone', battery: 5, charging: true)];
      expect(resolvePhoneBattery(devices).kind, BatteryGlyphKind.charging);
    });

    test(
      'picks the most-recently-seen phone device when there are several',
      () {
        final devices = [
          _device(
            kind: 'phone',
            sinceLastSeen: const Duration(minutes: 10),
            battery: 90,
            charging: false,
          ),
          _device(
            kind: 'phone',
            sinceLastSeen: Duration.zero,
            battery: 5,
            charging: false,
          ),
        ];
        final info = resolvePhoneBattery(devices);
        expect(info.kind, BatteryGlyphKind.low);
        expect(info.percent, 5);
      },
    );

    test(
      'an offline low-battery phone still gets flagged (not gated on isOnline)',
      () {
        final devices = [
          _device(
            kind: 'phone',
            sinceLastSeen: const Duration(hours: 2),
            battery: 4,
            charging: false,
          ),
        ];
        expect(resolvePhoneBattery(devices).kind, BatteryGlyphKind.low);
      },
    );
  });
}
