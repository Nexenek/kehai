import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/notifications/notification_decision.dart';
import 'package:couples_app/data/services/notifications/notification_hub.dart';
import 'package:couples_app/data/services/portal/portal_engine.dart';
import 'package:couples_app/data/services/portal/portal_knock_bridge.dart';
import 'package:couples_app/data/services/prefs_service.dart';

class _Recorder implements NotificationSink {
  final List<NotificationRequest> raised = [];

  @override
  Future<void> notify(NotificationRequest request) async => raised.add(request);
}

/// A whole [PortalCallSurface] with no engine behind it — same trick
/// `portal_call_screen_test.dart` uses, so the bridge can be driven through
/// knock/accept without a real transport layer.
class _FakeSurface extends ChangeNotifier implements PortalCallSurface {
  PortalState _state = PortalState.idle;
  String? _partnerId;
  final accepted = <String>[];

  @override
  PortalState get state => _state;

  @override
  String? lastError;

  @override
  String? get partnerId => _partnerId;

  @override
  Null get localRenderer => null;

  @override
  Null get remoteRenderer => null;

  @override
  Future<void> knock() async {}

  @override
  Future<void> accept() async => accepted.add('accept');

  @override
  Future<void> decline() async {}

  @override
  Future<void> hangUp() async {}

  /// Moves straight to `knocked`, as if a fresh knock from [from] had just
  /// arrived — the engine's own job (staleness, self-echo) is out of scope
  /// here; the bridge only ever reacts to the state it's handed.
  void knockFrom(String from) {
    _partnerId = from;
    _state = PortalState.knocked;
    notifyListeners();
  }

  void moveTo(PortalState next) {
    _state = next;
    notifyListeners();
  }
}

Future<PrefsService> _prefs({
  bool enabled = false,
  int fromHour = 17,
  int toHour = 22,
}) async {
  SharedPreferences.setMockInitialValues({
    'portal_auto_accept_enabled': enabled,
    'portal_auto_accept_from_hour': fromHour,
    'portal_auto_accept_to_hour': toHour,
  });
  return PrefsService.create();
}

void main() {
  group('shouldAutoAccept', () {
    test('disabled never fires, whatever the hour', () {
      expect(
        shouldAutoAccept(enabled: false, fromHour: 0, toHour: 23, hour: 12),
        isFalse,
      );
    });

    test('a plain (non-wrapping) range', () {
      expect(
        shouldAutoAccept(enabled: true, fromHour: 17, toHour: 22, hour: 18),
        isTrue,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 17, toHour: 22, hour: 17),
        isTrue,
      );
      // The end hour is exclusive.
      expect(
        shouldAutoAccept(enabled: true, fromHour: 17, toHour: 22, hour: 22),
        isFalse,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 17, toHour: 22, hour: 9),
        isFalse,
      );
    });

    test('a range that wraps past midnight', () {
      expect(
        shouldAutoAccept(enabled: true, fromHour: 22, toHour: 6, hour: 23),
        isTrue,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 22, toHour: 6, hour: 3),
        isTrue,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 22, toHour: 6, hour: 6),
        isFalse,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 22, toHour: 6, hour: 12),
        isFalse,
      );
    });

    test('from == to reads as the whole day', () {
      expect(
        shouldAutoAccept(enabled: true, fromHour: 9, toHour: 9, hour: 0),
        isTrue,
      );
      expect(
        shouldAutoAccept(enabled: true, fromHour: 9, toHour: 9, hour: 23),
        isTrue,
      );
    });
  });

  group('PortalKnockBridge', () {
    late _Recorder sink;
    late KehaiNotifications notifications;

    setUp(() {
      sink = _Recorder();
      notifications = KehaiNotifications(notifier: sink)
        ..myUserId = 'me'
        ..partnerName = 'kai'
        ..foregroundOverride = false;
    });

    test('a fresh knock reports a knock notification with the partner id', () async {
      final surface = _FakeSurface();
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(),
        isDesktop: () => true,
        isAppForeground: () => true,
      )..start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(sink.raised, hasLength(1));
      expect(sink.raised.single.eventKind, KehaiEventKind.knock);
      addTearDown(bridge.dispose);
    });

    test('a state change that is not a fresh knock reports nothing', () async {
      final surface = _FakeSurface();
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(),
        isDesktop: () => true,
        isAppForeground: () => true,
      )..start();

      surface.moveTo(PortalState.knocking);
      surface.moveTo(PortalState.idle);
      await Future<void>.delayed(Duration.zero);

      expect(sink.raised, isEmpty);
      addTearDown(bridge.dispose);
    });

    test('auto-accept is off by default — no accept, no bringToFront', () async {
      final surface = _FakeSurface();
      var broughtForward = 0;
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(),
        isDesktop: () => true,
        isAppForeground: () => true,
      );
      bridge.bringToFront = () => broughtForward++;
      bridge.start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(surface.accepted, isEmpty);
      expect(broughtForward, 0);
      addTearDown(bridge.dispose);
    });

    test('auto-accept fires on desktop within the window', () async {
      final surface = _FakeSurface();
      var broughtForward = 0;
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(enabled: true, fromHour: 17, toHour: 22),
        isDesktop: () => true,
        isAppForeground: () => false,
        now: () => DateTime(2026, 8, 24, 18),
      );
      bridge.bringToFront = () => broughtForward++;
      bridge.start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(surface.accepted, ['accept']);
      expect(broughtForward, 1);
      addTearDown(bridge.dispose);
    });

    test('auto-accept does not fire outside the window', () async {
      final surface = _FakeSurface();
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(enabled: true, fromHour: 17, toHour: 22),
        isDesktop: () => true,
        isAppForeground: () => true,
        now: () => DateTime(2026, 8, 24, 9),
      )..start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(surface.accepted, isEmpty);
      addTearDown(bridge.dispose);
    });

    test('on Android, auto-accept never fires from the background', () async {
      final surface = _FakeSurface();
      var broughtForward = 0;
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(enabled: true, fromHour: 0, toHour: 0),
        isDesktop: () => false,
        isAppForeground: () => false,
      );
      bridge.bringToFront = () => broughtForward++;
      bridge.start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(surface.accepted, isEmpty);
      expect(broughtForward, 0);
      addTearDown(bridge.dispose);
    });

    test('on Android, auto-accept fires while already foregrounded', () async {
      final surface = _FakeSurface();
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(enabled: true, fromHour: 0, toHour: 0),
        isDesktop: () => false,
        isAppForeground: () => true,
      )..start();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(surface.accepted, ['accept']);
      addTearDown(bridge.dispose);
    });

    test('dispose stops listening', () async {
      final surface = _FakeSurface();
      final bridge = PortalKnockBridge(
        engine: surface,
        notifications: notifications,
        prefs: await _prefs(),
        isDesktop: () => true,
        isAppForeground: () => true,
      )..start();
      bridge.dispose();

      surface.knockFrom('them');
      await Future<void>.delayed(Duration.zero);

      expect(sink.raised, isEmpty);
    });
  });
}
