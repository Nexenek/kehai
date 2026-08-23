import 'package:couples_app/data/services/background/partner_widget.dart';
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

PartnerStatus _status({
  String moodId = 'sleepy',
  String note = '',
  DateTime? updated,
}) {
  return PartnerStatus(
    userId: 'partner',
    moodId: moodId,
    note: note,
    sourceKind: SourceKind.phone,
    updated: updated ?? DateTime.now(),
  );
}

void main() {
  group('buildPartnerWidgetData', () {
    test('empty state when there is no partner yet', () {
      final data = buildPartnerWidgetData(
        partnerName: null,
        status: null,
        partnerDevices: const [],
      );
      expect(data, const PartnerWidgetData());
    });

    test('empty state when partner name is blank', () {
      final data = buildPartnerWidgetData(
        partnerName: '',
        status: _status(),
        partnerDevices: const [],
      );
      expect(data, const PartnerWidgetData());
    });

    test('maps partner name and mood kaomoji', () {
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(moodId: 'sleepy'),
        partnerDevices: const [],
      );
      expect(data.partnerName, 'mati');
      expect(data.moodKaomoji, '(￣o￣) zzZ');
    });

    test('no kaomoji when the partner has no status yet', () {
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: null,
        partnerDevices: const [],
      );
      expect(data.partnerName, 'mati');
      expect(data.moodKaomoji, isNull);
      expect(data.updatedEpochMs, isNull);
    });

    test(
      'ambient line reuses the shared precedence (now playing beats away)',
      () {
        final data = buildPartnerWidgetData(
          partnerName: 'mati',
          status: _status(),
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
        expect(data.ambientLine, '♪ Marigold — Periphery');
      },
    );

    test('falls back to "away" when nothing is online', () {
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [_device(seenAgo: const Duration(minutes: 30))],
      );
      expect(data.ambientLine, AppStrings.ambientAway);
    });

    test('falls back to "away" when there are no devices at all', () {
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: const [],
      );
      expect(data.ambientLine, AppStrings.ambientAway);
    });

    test('idle past 5 minutes reads as away', () {
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(),
        partnerDevices: [_device(idleSeconds: 600)],
      );
      expect(data.ambientLine, AppStrings.ambientAway);
    });

    test('updatedEpochMs mirrors the status timestamp, not the clock', () {
      final updated = DateTime.utc(2026, 8, 20, 12, 0, 0);
      final data = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(updated: updated),
        partnerDevices: const [],
      );
      expect(data.updatedEpochMs, updated.millisecondsSinceEpoch);
    });

    test('equal inputs produce equal data', () {
      final devices = [_device()];
      final updated = DateTime.now();
      final a = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(updated: updated),
        partnerDevices: devices,
      );
      final b = buildPartnerWidgetData(
        partnerName: 'mati',
        status: _status(updated: updated),
        partnerDevices: devices,
      );
      expect(a, b);
    });
  });
}
