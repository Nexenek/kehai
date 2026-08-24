import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/portal_signal_repository.dart';
import 'package:couples_app/domain/models/portal_signal.dart';

RecordModel _record({
  String kind = 'offer',
  String from = 'partner',
  Map<String, dynamic>? payload,
  String created = '2026-08-24 12:00:00.000Z',
}) => RecordModel({
  'id': 'sig1',
  'collectionId': 'c',
  'collectionName': 'portal_signals',
  'couple': 'couple1',
  'from': from,
  'kind': kind,
  'payload': payload,
  'created': created,
});

void main() {
  group('portalSignalFromRecord', () {
    test('maps a signal off the wire', () {
      final signal = portalSignalFromRecord(
        _record(kind: 'ice', payload: {'candidate': 'a', 'sdpMLineIndex': 0}),
      )!;

      expect(signal.id, 'sig1');
      expect(signal.fromId, 'partner');
      expect(signal.kind, PortalSignalKind.ice);
      expect(signal.payload['candidate'], 'a');
      expect(signal.created.isUtc, isFalse); // localized, like every other one
    });

    test('a missing payload reads as empty, not null', () {
      final signal = portalSignalFromRecord(_record(kind: 'knock'))!;
      expect(signal.payload, isEmpty);
    });

    test('a kind this build has never heard of is dropped', () {
      expect(portalSignalFromRecord(_record(kind: 'telepathy')), isNull);
    });
  });

  group('PortalSignalKind', () {
    test('the wire values match the server select, exactly', () {
      // server/migrations/16_portal.go's Values list, in order.
      expect(PortalSignalKind.values.map((k) => k.id), [
        'knock',
        'accept',
        'decline',
        'offer',
        'answer',
        'ice',
        'hangup',
      ]);
    });

    test('byId round-trips every kind', () {
      for (final kind in PortalSignalKind.values) {
        expect(PortalSignalKind.byId(kind.id), kind);
      }
      expect(PortalSignalKind.byId(''), isNull);
    });
  });
}
