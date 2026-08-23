import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ambient_line.dart';
import 'package:couples_app/domain/models/mood.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
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
            onExpand: onExpand,
            onDragStart: onDragStart,
            transparentCorners: transparentCorners,
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
}
