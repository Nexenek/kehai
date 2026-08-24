// Throwaway README-screenshot generator — run with --update-goldens to
// (re)render docs/screenshots/mini-card.png. Not part of the suite's
// assertions; it exists so the README's mini-card image is reproducible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ambient_line.dart';
import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/heart_rate_sample.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/data/services/portal/portal_engine.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/mini_partner_window.dart';
import 'package:couples_app/ui/features/portal/portal_call_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pixel_fonts.dart';

class _StillSurface extends ChangeNotifier implements PortalCallSurface {
  @override
  PortalState get state => PortalState.idle;
  @override
  String? get lastError => null;
  @override
  String? get partnerId => null;
  @override
  Null get localRenderer => null;
  @override
  Null get remoteRenderer => null;
  @override
  Future<void> knock() async {}
  @override
  Future<void> accept() async {}
  @override
  Future<void> decline() async {}
  @override
  Future<void> hangUp() async {}
}

void main() {
  setUpAll(loadPixelFonts);

  // Render-only: these exist to (re)generate the README images, not to
  // gate the suite — a normal `flutter test` run skips them so an
  // intentional UI change never fails CI over a stale docs pixel.
  // Regenerate with: flutter test --update-goldens test/readme_screenshot_test.dart
  testWidgets('render the mini card for the README', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(480, 300);
    addTearDown(tester.view.reset);

    final phone = DeviceStatus(
      id: 'd1',
      ownerId: 'mio',
      name: "mio's phone",
      kind: 'phone',
      lastSeen: DateTime.now().toUtc(),
      nowPlaying: const NowPlaying(
        title: 'Plastic Love',
        artist: 'Mariya Takeuchi',
        album: '',
        player: 'Spotify',
        state: NowPlayingState.playing,
      ),
      idleSeconds: 12,
      battery: 67,
      heartRate: HeartRateSample(bpm: 72, at: DateTime.now().toUtc()),
      stepsToday: 6124,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: MiniPartnerWindow(
            partnerName: 'mio',
            status: PartnerStatus(
              userId: 'mio',
              moodId: 'cozy',
              note: '',
              sourceKind: SourceKind.phone,
              updated: DateTime.now(),
            ),
            phoneOnline: true,
            desktopOnline: false,
            ambientLine: const AmbientLine(
              kind: AmbientLineKind.nowPlaying,
              text: '♪ Plastic Love — Mariya Takeuchi',
            ),
            onSendPing: () {},
            partnerDevices: [phone],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MiniPartnerWindow),
      matchesGoldenFile('../../docs/screenshots/mini-card.png'),
    );
  });

  testWidgets('render the portal curtain for the README', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(720, 960);
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = PrefsService(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: PortalCallScreen(engine: _StillSurface(), prefs: prefs),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(PortalCallScreen),
      matchesGoldenFile('../../docs/screenshots/portal-curtain.png'),
    );
  });
}
