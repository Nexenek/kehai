import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/ping_repository.dart';
import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/notifications/notification_decision.dart';
import 'package:couples_app/data/services/notifications/notification_hub.dart';
import 'package:couples_app/domain/models/ping.dart';
import 'package:couples_app/ui/features/pings/ping_send_logic.dart';
import 'package:couples_app/ui/features/pings/ping_view_model.dart';

/// Records sends and lets a test push a ping straight into whatever callback
/// [PingViewModel.init] registered — same shape as
/// `_FakeTouchRepository` in thumb_kiss_view_model_test.dart.
class _FakePingRepository extends PingRepository {
  _FakePingRepository() : super(PocketBase('http://127.0.0.1:1'));

  final sent = <PingKind>[];
  void Function(Ping ping)? _onPing;

  @override
  Future<void> send({
    required String coupleId,
    required String fromId,
    required PingKind kind,
  }) async {
    sent.add(kind);
  }

  @override
  Future<UnsubscribeFunc> subscribe(void Function(Ping ping) onPing) async {
    _onPing = onPing;
    return () async {};
  }

  void emit(Ping ping) => _onPing?.call(ping);
}

class _Recorder implements NotificationSink {
  final raised = <NotificationRequest>[];

  @override
  Future<void> notify(NotificationRequest request) async => raised.add(request);
}

AuthRepository _loggedIn({String id = 'me', String couple = 'couple1'}) {
  final pb = PocketBase('https://example.invalid');
  pb.authStore.save(
    'tok',
    RecordModel({
      'id': id,
      'collectionId': 'c',
      'collectionName': 'users',
      'couple': couple,
    }),
  );
  return AuthRepository(pb);
}

Ping _ping({
  String from = 'them',
  String couple = 'couple1',
  PingKind kind = PingKind.thinking,
}) => Ping(
  id: 'p1',
  coupleId: couple,
  fromId: from,
  kind: kind,
  created: DateTime.now(),
);

void main() {
  late _FakePingRepository repository;
  late _Recorder sink;
  late KehaiNotifications hub;
  late DateTime now;

  PingViewModel build() => PingViewModel(
    authRepository: _loggedIn(),
    pingRepository: repository,
    notifications: hub,
    now: () => now,
  );

  setUp(() {
    repository = _FakePingRepository();
    sink = _Recorder();
    hub = KehaiNotifications(notifier: sink)
      ..myUserId = 'me'
      ..partnerName = 'mati'
      ..foregroundOverride = false;
    now = DateTime(2026, 8, 24, 12, 0, 0);
  });

  group('sending', () {
    test('the first ping goes out as "thinking"', () async {
      final vm = build();
      expect(await vm.send(), isTrue);
      expect(repository.sent, [PingKind.thinking]);
      expect(vm.justSent, isTrue);
      vm.dispose();
    });

    test('a second tap inside the debounce is dropped', () async {
      final vm = build();
      await vm.send();
      now = now.add(const Duration(milliseconds: 500));
      expect(await vm.send(PingKind.hug), isFalse);
      expect(repository.sent, [PingKind.thinking]);
      vm.dispose();
    });

    test('once the debounce lapses it sends again', () async {
      final vm = build();
      await vm.send();
      now = now.add(pingDebounce);
      expect(await vm.send(PingKind.kiss), isTrue);
      expect(repository.sent, [PingKind.thinking, PingKind.kiss]);
      vm.dispose();
    });

    test('canSend mirrors the debounce so the button can grey out', () async {
      final vm = build();
      expect(vm.canSend, isTrue);
      await vm.send();
      expect(vm.canSend, isFalse);
      now = now.add(pingDebounce);
      expect(vm.canSend, isTrue);
      vm.dispose();
    });

    test('a failing send still counts against the debounce', () async {
      // Otherwise a server hiccup turns into a stream of retries on the
      // partner's phone the moment it comes back.
      final vm = build();
      await vm.send();
      expect(vm.canSend, isFalse);
      vm.dispose();
    });
  });

  group('receiving', () {
    test("a partner's ping notifies and shows on the card", () async {
      final vm = build();
      await vm.init();

      repository.emit(_ping(kind: PingKind.kiss));
      await Future<void>.delayed(Duration.zero);

      expect(vm.lastReceived?.kind, PingKind.kiss);
      expect(sink.raised, hasLength(1));
      expect(sink.raised.single.eventKind, KehaiEventKind.ping);
      vm.dispose();
    });

    test('my own ping echoing back does neither', () async {
      final vm = build();
      await vm.init();

      repository.emit(_ping(from: 'me'));
      await Future<void>.delayed(Duration.zero);

      expect(vm.lastReceived, isNull);
      expect(sink.raised, isEmpty);
      vm.dispose();
    });

    test('another couple\'s ping is ignored entirely', () async {
      final vm = build();
      await vm.init();

      repository.emit(_ping(couple: 'someone_else'));
      await Future<void>.delayed(Duration.zero);

      expect(vm.lastReceived, isNull);
      expect(sink.raised, isEmpty);
      vm.dispose();
    });

    test('losing the partner clears the received line', () async {
      final vm = build();
      await vm.init();
      vm.updatePartner('them');
      repository.emit(_ping());
      await Future<void>.delayed(Duration.zero);
      expect(vm.lastReceived, isNotNull);

      vm.updatePartner(null);
      expect(vm.lastReceived, isNull);
      vm.dispose();
    });
  });
}
