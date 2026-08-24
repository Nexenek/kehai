import 'package:couples_app/data/services/presence/android/android_presence_channel.dart';
import 'package:couples_app/data/services/presence/android/vitals_channel.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/settings/view_models/phone_superpowers_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The vitals row's grant states, driven through a faked [VitalsChannel].
///
/// Two on-device failures this covers, both of which shipped once:
///
/// 1. The permission request came back false having shown the user nothing
///    at all, and the row just… didn't turn on. It now falls through to
///    Health Connect's settings and says so.
/// 2. Reads were granted but background reads weren't, so vitals only moved
///    while the app was open — with nothing anywhere admitting that. The row
///    now warns and offers the way to fix it.
class _FakeVitalsChannel implements VitalsChannel {
  _FakeVitalsChannel({
    this.availabilityResult = VitalsAvailability.available,
    this.granted = false,
    this.backgroundGranted = false,
    this.grantOnRequest = false,
    this.settingsOpen = true,
    this.reading = VitalsReading.empty,
  });

  VitalsAvailability availabilityResult;
  bool granted;
  bool backgroundGranted;

  /// What the permission flow does: true means the user said yes, false is
  /// both "said no" and "the sheet never appeared" — indistinguishable from
  /// here, which is exactly why the fallback treats them the same.
  bool grantOnRequest;

  /// Whether the phone can resolve the Health Connect settings intent.
  bool settingsOpen;

  VitalsReading reading;

  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<VitalsAvailability> availability() async => availabilityResult;

  @override
  Future<bool> hasPermissions() async => granted;

  @override
  Future<bool> hasBackgroundPermission() async => backgroundGranted;

  @override
  Future<bool> requestPermissions() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return settingsOpen;
  }

  @override
  Future<VitalsReading> read() async => reading;
}

/// The presence half of the screen is irrelevant here, but the constructor
/// starts polling it — so it gets a fake too rather than a real platform
/// channel that would throw on every tick.
class _SilentPresenceChannel implements AndroidPresenceChannel {
  @override
  Stream<Object?> get events => const Stream<Object?>.empty();

  @override
  Future<Object?> snapshot() async => null;

  @override
  Future<bool> isNotificationListenerEnabled() async => false;

  @override
  Future<bool> openNotificationListenerSettings() async => false;

  @override
  Future<bool> hasUsageAccess() async => false;

  @override
  Future<bool> openUsageAccessSettings() async => false;

  @override
  Future<void> setForegroundAppEnabled(bool enabled) async {}

  @override
  Future<String?> getForegroundAppPreview() async => null;
}

PhoneSuperpowersViewModel _viewModel(
  _FakeVitalsChannel vitals, {
  bool initialShareVitals = false,
  List<bool>? setCalls,
}) {
  final model = PhoneSuperpowersViewModel(
    presenceChannel: _SilentPresenceChannel(),
    vitalsChannel: vitals,
    initialShareFocusedApp: false,
    initialShareUnknownApps: false,
    initialShareLocation: false,
    initialShareVitals: initialShareVitals,
    onSetShareFocusedApp: (_) async {},
    onSetShareUnknownApps: (_) async {},
    onSetShareLocation: (_) async {},
    onSetShareVitals: (value) async => setCalls?.add(value),
    // Long enough that the preview timer never fires during a test.
    activityPreviewInterval: const Duration(days: 1),
    isSupportedOverride: true,
  );
  addTearDown(model.dispose);
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('vitals row — turning it on', () {
    test(
      'a granted request flips the toggle and tells AppController',
      () async {
        final channel = _FakeVitalsChannel(
          grantOnRequest: true,
          backgroundGranted: true,
          reading: const VitalsReading(stepsToday: 4231),
        );
        final calls = <bool>[];
        final model = _viewModel(channel, setCalls: calls);

        await model.setShareVitals(true);

        expect(model.shareVitals, isTrue);
        expect(calls, [true]);
        expect(model.vitalsGranted, isTrue);
        expect(model.vitalsMessage, isNull);
        expect(channel.settingsOpened, 0);
      },
    );

    test('a request that grants nothing falls through to health connect '
        'settings instead of silently doing nothing', () async {
      final channel = _FakeVitalsChannel(grantOnRequest: false);
      final calls = <bool>[];
      final model = _viewModel(channel, setCalls: calls);

      await model.setShareVitals(true);

      // The toggle stays honest — nothing can be read, so nothing is shared.
      expect(model.shareVitals, isFalse);
      expect(calls, isEmpty);
      expect(channel.requests, 1);
      expect(channel.settingsOpened, 1);
      expect(model.vitalsMessage, AppStrings.vitalsGrantFallback);
      expect(model.vitalsCanOpenSettings, isTrue);
    });

    test('a phone that cannot even open those settings says so', () async {
      final channel = _FakeVitalsChannel(
        grantOnRequest: false,
        settingsOpen: false,
      );
      final model = _viewModel(channel);

      await model.setShareVitals(true);

      expect(model.vitalsMessage, AppStrings.vitalsSettingsUnavailable);
    });

    test(
      'no health connect at all: the toggle refuses and never asks',
      () async {
        final channel = _FakeVitalsChannel(
          availabilityResult: VitalsAvailability.unavailable,
        );
        final model = _viewModel(channel);

        await model.setShareVitals(true);

        expect(model.shareVitals, isFalse);
        expect(channel.requests, 0);
        expect(model.vitalsUnavailable, isTrue);
      },
    );

    test(
      'already granted: the toggle flips without a permission round-trip',
      () async {
        final channel = _FakeVitalsChannel(
          granted: true,
          backgroundGranted: true,
        );
        final model = _viewModel(channel);
        await model.refreshVitalsForTest();

        await model.setShareVitals(true);

        expect(model.shareVitals, isTrue);
        expect(channel.requests, 0);
      },
    );
  });

  group('vitals row — background access', () {
    test(
      'granted reads without background access warn, and offer the fix',
      () async {
        final channel = _FakeVitalsChannel(
          granted: true,
          backgroundGranted: false,
          reading: const VitalsReading(stepsToday: 4231),
        );
        final model = _viewModel(channel, initialShareVitals: true);

        await model.refreshVitalsForTest();

        expect(model.vitalsForegroundOnly, isTrue);
        expect(model.vitalsMessage, AppStrings.vitalsForegroundOnly);
        expect(model.vitalsCanOpenSettings, isTrue);
      },
    );

    test('with background access there is nothing to warn about', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: true,
        reading: const VitalsReading(stepsToday: 4231),
      );
      final model = _viewModel(channel, initialShareVitals: true);

      await model.refreshVitalsForTest();

      expect(model.vitalsForegroundOnly, isFalse);
      expect(model.vitalsMessage, isNull);
      expect(model.vitalsCanOpenSettings, isFalse);
    });

    test('the warning is about sharing, so it stays quiet while the opt-in '
        'is off', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: false,
      );
      final model = _viewModel(channel);

      await model.refreshVitalsForTest();

      expect(model.vitalsForegroundOnly, isFalse);
      expect(model.vitalsMessage, isNull);
    });

    test('opening the settings from the warning reaches the channel', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: false,
      );
      final model = _viewModel(channel, initialShareVitals: true);

      await model.openVitalsSettings();

      expect(channel.settingsOpened, 1);
    });

    test('an unresolvable settings intent surfaces its own line', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: false,
        settingsOpen: false,
      );
      final model = _viewModel(channel, initialShareVitals: true);

      await model.openVitalsSettings();

      expect(model.vitalsMessage, AppStrings.vitalsSettingsUnavailable);
    });
  });

  group('vitals row — waiting for the watch', () {
    test('granted and sharing but nothing synced yet', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: true,
        reading: VitalsReading.empty,
      );
      final model = _viewModel(channel, initialShareVitals: true);

      await model.refreshVitalsForTest();

      expect(model.vitalsWaitingForData, isTrue);
    });

    test('a real reading clears it', () async {
      final channel = _FakeVitalsChannel(
        granted: true,
        backgroundGranted: true,
        reading: const VitalsReading(stepsToday: 4231),
      );
      final model = _viewModel(channel, initialShareVitals: true);

      await model.refreshVitalsForTest();

      expect(model.vitalsWaitingForData, isFalse);
    });
  });
}
