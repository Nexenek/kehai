import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ambient_line.dart';
import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/heart_rate_sample.dart';
import 'package:couples_app/domain/models/mood.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/domain/models/ping.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/pixel_heart.dart';
import 'package:couples_app/ui/features/home/views/mini_partner_window.dart';

import 'support/pixel_fonts.dart';

PartnerStatus _status(String moodId) => PartnerStatus(
  userId: 'them',
  moodId: moodId,
  note: 'a note nobody reads in the little window',
  sourceKind: SourceKind.desktop,
  updated: DateTime.now(),
);

void main() {
  setUpAll(loadPixelFonts);

  Future<void> pumpCard(
    WidgetTester tester, {
    PartnerStatus? status,
    AmbientLine? ambientLine,
    VoidCallback? onExpand,
    VoidCallback? onDragStart,
    bool phoneOnline = false,
    bool desktopOnline = false,
    bool transparentCorners = false,
    VoidCallback? onSendPing,
    bool canSendPing = true,
    bool pingJustSent = false,
    Ping? receivedPing,
    List<DeviceStatus> partnerDevices = const [],
  }) async {
    // The real thing: 240×150, the size DesktopWindowService gives it.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(240, 150);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: MiniPartnerWindow(
            partnerName: 'mati',
            status: status,
            phoneOnline: phoneOnline,
            desktopOnline: desktopOnline,
            ambientLine: ambientLine,
            onSendPing: onSendPing,
            canSendPing: canSendPing,
            pingJustSent: pingJustSent,
            receivedPing: receivedPing,
            onExpand: onExpand,
            onDragStart: onDragStart,
            transparentCorners: transparentCorners,
            partnerDevices: partnerDevices,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the mood kaomoji large, and who it belongs to', (
    tester,
  ) async {
    await pumpCard(tester, status: _status('sleepy'));

    final sleepy = MoodCatalog.byId('sleepy');
    expect(find.text(sleepy.kaomoji), findsOneWidget);
    expect(find.text('mati'), findsOneWidget);
    // The card is a glance, not a screen: the note stays in the panel.
    expect(find.textContaining('a note nobody reads'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the portrait slot is what a sprite will replace later', (
    tester,
  ) async {
    await pumpCard(tester, status: _status('happy'));

    // The kaomoji lives inside its own widget with its own slot, so swapping
    // in character art doesn't reflow the card around it.
    expect(find.byType(PartnerPortrait), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PartnerPortrait),
        matching: find.text(MoodCatalog.byId('happy').kaomoji),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the ambient line rides under the portrait', (tester) async {
    await pumpCard(
      tester,
      status: _status('gaming'),
      ambientLine: const AmbientLine(
        kind: AmbientLineKind.nowPlaying,
        text: '♪ Cornfield Chase — Hans Zimmer',
      ),
    );

    expect(find.textContaining('Cornfield Chase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the mood label when nothing ambient is known', (
    tester,
  ) async {
    await pumpCard(tester, status: _status('cozy'));

    expect(find.text(MoodCatalog.byId('cozy').label), findsOneWidget);
  });

  testWidgets('says so plainly when there is nobody to show yet', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.text(AppStrings.miniNobodyYet), findsOneWidget);
  });

  testWidgets('clicking the card expands, dragging it moves the window', (
    tester,
  ) async {
    var expands = 0;
    var drags = 0;
    await pumpCard(
      tester,
      status: _status('happy'),
      onExpand: () => expands++,
      onDragStart: () => drags++,
    );

    await tester.tap(find.byType(MiniPartnerWindow));
    await tester.pump();
    expect(expands, 1);

    await tester.drag(find.byType(MiniPartnerWindow), const Offset(60, 30));
    await tester.pump();
    expect(drags, 1);
    // A drag is not a click — it must not have opened the panel too.
    expect(expands, 1);
  });

  testWidgets('device glyphs are on the card', (tester) async {
    await pumpCard(tester, status: _status('working'), desktopOnline: true);

    expect(find.byTooltip(AppStrings.onDesktopTooltip), findsWidgets);
  });

  group('when the window behind it is genuinely transparent', () {
    testWidgets('the card drops its opaque fill — only the border remains', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status: _status('happy'),
        transparentCorners: true,
      );

      final decoratedBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .toList();
      final cardBox = decoratedBoxes.firstWhere(
        (box) => (box.decoration as BoxDecoration).border != null,
      );
      expect((cardBox.decoration as BoxDecoration).color, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays opaque-filled when transparency is not active', (
      tester,
    ) async {
      await pumpCard(tester, status: _status('happy'));

      final decoratedBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .toList();
      final cardBox = decoratedBoxes.firstWhere(
        (box) => (box.decoration as BoxDecoration).border != null,
      );
      expect((cardBox.decoration as BoxDecoration).color, isNotNull);
    });

    testWidgets('the kaomoji gets a legibility halo so it reads on any '
        'desktop background', (tester) async {
      await pumpCard(
        tester,
        status: _status('happy'),
        transparentCorners: true,
      );

      final kaomoji = tester.widget<Text>(
        find.descendant(
          of: find.byType(PartnerPortrait),
          matching: find.text(MoodCatalog.byId('happy').kaomoji),
        ),
      );
      expect(kaomoji.style?.shadows, isNotNull);
      expect(kaomoji.style!.shadows!, isNotEmpty);
    });

    testWidgets('no halo when the card has its own opaque background', (
      tester,
    ) async {
      await pumpCard(tester, status: _status('happy'));

      final kaomoji = tester.widget<Text>(
        find.descendant(
          of: find.byType(PartnerPortrait),
          matching: find.text(MoodCatalog.byId('happy').kaomoji),
        ),
      );
      expect(kaomoji.style?.shadows, isNull);
    });
  });

  group('the little ♥', () {
    testWidgets('is absent until there is somewhere to send it', (
      tester,
    ) async {
      await pumpCard(tester, status: _status('happy'));
      expect(find.byKey(const Key('mini-ping-heart')), findsNothing);
    });

    testWidgets('sends without also expanding the window', (tester) async {
      var pinged = 0;
      var expanded = 0;
      await pumpCard(
        tester,
        status: _status('happy'),
        onSendPing: () => pinged++,
        onExpand: () => expanded++,
      );

      await tester.tap(find.byKey(const Key('mini-ping-heart')));
      await tester.pump();

      expect(pinged, 1);
      expect(expanded, 0, reason: 'the tap must not fall through to the card');
    });

    testWidgets('still fits the real 240x150 card', (tester) async {
      await pumpCard(
        tester,
        status: _status('cozy'),
        ambientLine: const AmbientLine(
          kind: AmbientLineKind.nowPlaying,
          text: 'a long enough now-playing line to squeeze the row',
        ),
        phoneOnline: true,
        desktopOnline: true,
        onSendPing: () {},
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the compact vitals form (beating heart + bpm only)', () {
    testWidgets('a fresh heart-rate sample shows the heart and bpm', (
      tester,
    ) async {
      final phone = DeviceStatus(
        id: 'd1',
        ownerId: 'partner',
        name: 'phone',
        kind: 'phone',
        lastSeen: DateTime.now().toUtc(),
        heartRate: HeartRateSample(
          bpm: 72,
          at: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        ),
      );
      await pumpCard(tester, status: _status('happy'), partnerDevices: [phone]);

      expect(find.byKey(const Key('mini-vitals-line')), findsOneWidget);
      expect(find.byType(PixelHeart), findsOneWidget);
      expect(find.text(AppStrings.vitalsBpm(72)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('steps alone (no fresh bpm) show nothing — mini has no '
        'room for the steps half', (tester) async {
      final phone = DeviceStatus(
        id: 'd1',
        ownerId: 'partner',
        name: 'phone',
        kind: 'phone',
        lastSeen: DateTime.now().toUtc(),
        stepsToday: 4231,
      );
      await pumpCard(tester, status: _status('happy'), partnerDevices: [phone]);

      expect(find.byKey(const Key('mini-vitals-line')), findsNothing);
      expect(find.byType(PixelHeart), findsNothing);
    });

    testWidgets('a stale heart-rate sample shows nothing', (tester) async {
      final phone = DeviceStatus(
        id: 'd1',
        ownerId: 'partner',
        name: 'phone',
        kind: 'phone',
        lastSeen: DateTime.now().toUtc(),
        heartRate: HeartRateSample(
          bpm: 72,
          at: DateTime.now().toUtc().subtract(
            HeartRateSample.freshWindow + const Duration(minutes: 1),
          ),
        ),
      );
      await pumpCard(tester, status: _status('happy'), partnerDevices: [phone]);

      expect(find.byKey(const Key('mini-vitals-line')), findsNothing);
      expect(find.byType(PixelHeart), findsNothing);
    });

    testWidgets('with no partner devices, nothing shows and the card still '
        'fits the real 240x150 size', (tester) async {
      await pumpCard(tester, status: _status('happy'));

      expect(find.byKey(const Key('mini-vitals-line')), findsNothing);
      expect(find.byType(PixelHeart), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('a ping arriving while the card is all that is on screen', () {
    Ping ping(PingKind kind) => Ping(
      id: 'p1',
      coupleId: 'c1',
      fromId: 'them',
      kind: kind,
      created: DateTime.now(),
    );

    testWidgets('borrows the bottom line, outranking the ambient text', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status: _status('happy'),
        ambientLine: const AmbientLine(
          kind: AmbientLineKind.nowPlaying,
          text: '♪ Cornfield Chase — Hans Zimmer',
        ),
        receivedPing: ping(PingKind.thinking),
      );

      expect(find.byKey(const Key('mini-ping-line')), findsOneWidget);
      expect(
        find.textContaining("they're thinking of you"),
        findsOneWidget,
      );
      expect(find.textContaining('Cornfield Chase'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names the kind — a kiss reads as a kiss', (tester) async {
      await pumpCard(
        tester,
        status: _status('happy'),
        receivedPing: ping(PingKind.kiss),
      );

      expect(
        find.text(AppStrings.pingReceivedLine(PingKind.kiss)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('and once it fades, the ambient line is back', (tester) async {
      await pumpCard(
        tester,
        status: _status('happy'),
        ambientLine: const AmbientLine(
          kind: AmbientLineKind.nowPlaying,
          text: '♪ Cornfield Chase — Hans Zimmer',
        ),
      );

      expect(find.byKey(const Key('mini-ping-line')), findsNothing);
      expect(find.textContaining('Cornfield Chase'), findsOneWidget);
    });
  });
}
