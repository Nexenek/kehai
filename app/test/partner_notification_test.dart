import 'package:couples_app/data/services/background/partner_notification.dart';
import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceStatus _device({
  String id = 'd1',
  String kind = 'phone',
  Duration seenAgo = Duration.zero,
  NowPlaying? nowPlaying,
  int? idleSeconds,
  String? activity,
}) {
  return DeviceStatus(
    id: id,
    ownerId: 'partner',
    name: 'their $kind',
    kind: kind,
    lastSeen: DateTime.now().subtract(seenAgo),
    nowPlaying: nowPlaying,
    idleSeconds: idleSeconds,
    activity: activity,
  );
}

PartnerStatus _status({String moodId = 'sleepy', String note = ''}) {
  return PartnerStatus(
    userId: 'partner',
    moodId: moodId,
    note: note,
    sourceKind: SourceKind.phone,
    updated: DateTime.now(),
  );
}

void main() {
  group('buildPartnerNotification', () {
    test('titles with the partner name and their mood kaomoji', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(moodId: 'sleepy'),
        partnerDevices: const [],
      );
      expect(content.title, 'mati  (￣o￣) zzZ');
    });

    test('falls back to just the name when there is no status yet', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: null,
        partnerDevices: const [],
      );
      expect(content.title, 'mati');
    });

    test('shows the waiting copy before a partner joins', () {
      final content = buildPartnerNotification(
        partnerName: null,
        status: null,
        partnerDevices: const [],
      );
      expect(content.title, AppStrings.notificationWaitingTitle);
      expect(content.text, AppStrings.notificationWaitingText);
    });

    test('body stacks note, ambient line and device indicator', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(note: 'making tea'),
        partnerDevices: [
          _device(
            nowPlaying: const NowPlaying(
              title: 'Marigold',
              artist: 'Periphery',
              state: NowPlayingState.playing,
            ),
          ),
        ],
      );

      expect(content.text.split('\n'), [
        'making tea',
        '♪ Marigold — Periphery',
        AppStrings.notificationDevicesPhone,
      ]);
    });

    test('omits an empty note instead of leaving a blank line', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(note: '   '),
        partnerDevices: [_device()],
      );
      expect(content.text.split('\n'), [
        AppStrings.ambientOnPhone,
        AppStrings.notificationDevicesPhone,
      ]);
    });

    test('reuses the shared ambient precedence, not a second copy of it', () {
      // activity outranks the "on their phone" rung, exactly as it does on
      // the partner card — proof this goes through resolveAmbientLine.
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [_device(activity: 'gaming')],
      );
      expect(content.text.split('\n').first, 'gaming');
    });

    test('idle past 5 minutes reads as away', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [_device(idleSeconds: 600)],
      );
      expect(content.text.split('\n').first, AppStrings.ambientAway);
    });

    test('names both devices when both are online', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [
          _device(id: 'a', kind: 'phone'),
          _device(id: 'b', kind: 'desktop'),
        ],
      );
      expect(content.text.split('\n').last, AppStrings.notificationDevicesBoth);
    });

    test('stale devices count as offline', () {
      final content = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [_device(seenAgo: const Duration(minutes: 30))],
      );
      // Nothing online: no ambient line at all, and the device row says so.
      expect(content.text, AppStrings.notificationDevicesNone);
    });

    test('equal inputs produce equal content, so re-renders can be skipped', () {
      final devices = [_device()];
      final a = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(note: 'hi'),
        partnerDevices: devices,
      );
      final b = buildPartnerNotification(
        partnerName: 'mati',
        status: _status(note: 'hi'),
        partnerDevices: devices,
      );
      expect(a, b);
    });
  });
}
