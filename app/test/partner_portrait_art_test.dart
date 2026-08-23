import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/art_scene.dart';
import 'package:couples_app/domain/models/mood.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/ui/features/art/art_scene_view.dart';
import 'package:couples_app/ui/features/home/views/mini_partner_window.dart';
import 'package:couples_app/ui/features/home/views/partner_card.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';

import 'support/pixel_fonts.dart';

ArtLayer _layer(String id, ArtSlot slot) => ArtLayer(
  id: id,
  coupleId: 'couple1',
  slot: slot,
  name: id,
  imageUrl: 'https://example.invalid/api/files/art_layers/$id/l.png',
);

PartnerStatus _status(String moodId) => PartnerStatus(
  userId: 'them',
  moodId: moodId,
  note: '',
  sourceKind: SourceKind.desktop,
  updated: DateTime.now(),
);

void main() {
  setUpAll(loadPixelFonts);

  group('PartnerPortrait', () {
    testWidgets('with no scene it is the mood kaomoji — the fallback is a '
        'complete answer, not a placeholder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: PartnerPortrait(mood: MoodCatalog.byId('sleepy')),
            ),
          ),
        ),
      );

      expect(find.text(MoodCatalog.byId('sleepy').kaomoji), findsOneWidget);
      expect(find.byType(ArtSceneView), findsNothing);
    });

    testWidgets('with a scene it stacks the layers, bottom first, with no '
        'filtering', (tester) async {
      final scene = [
        _layer('bg', ArtSlot.background),
        _layer('body', ArtSlot.base),
        _layer('face', ArtSlot.expression),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: PartnerPortrait(
                mood: MoodCatalog.byId('sleepy'),
                scene: scene,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ArtSceneView), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.map((i) => i.key).toList(), const [
        ValueKey('bg'),
        ValueKey('body'),
        ValueKey('face'),
      ]);
      for (final image in images) {
        expect(image.filterQuality, FilterQuality.none);
      }
      // The art replaces the kaomoji rather than sitting next to it.
      expect(find.text(MoodCatalog.byId('sleepy').kaomoji), findsNothing);
    });

    testWidgets('the canvas is square even in a non-square slot', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: PartnerPortrait(
                mood: null,
                scene: [_layer('body', ArtSlot.base)],
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(Image));
      expect(size.width, size.height);
      expect(size.height, lessThanOrEqualTo(120));
    });
  });

  group('the little window', () {
    Future<void> pumpMini(WidgetTester tester, List<ArtLayer> scene) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(240, 150);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MiniPartnerWindow(
              partnerName: 'mati',
              status: _status('happy'),
              phoneOnline: false,
              desktopOnline: true,
              artScene: scene,
            ),
          ),
        ),
      );
    }

    testWidgets('shows the art when a scene resolves', (tester) async {
      await pumpMini(tester, [_layer('body', ArtSlot.base)]);

      expect(find.byType(ArtSceneView), findsOneWidget);
      expect(find.text(MoodCatalog.byId('happy').kaomoji), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the kaomoji when no scene resolves', (tester) async {
      await pumpMini(tester, const []);

      expect(find.byType(ArtSceneView), findsNothing);
      expect(find.text(MoodCatalog.byId('happy').kaomoji), findsOneWidget);
    });
  });

  group('the big partner card', () {
    Future<void> pumpCard(WidgetTester tester, List<ArtLayer> scene) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerCard(
                partnerName: 'mati',
                status: _status('cozy'),
                phoneOnline: true,
                desktopOnline: false,
                artScene: scene,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders the same composited stack as the little window', (
      tester,
    ) async {
      await pumpCard(tester, [
        _layer('body', ArtSlot.base),
        _layer('mug', ArtSlot.prop),
      ]);

      expect(find.byType(ArtSceneView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ArtSceneView),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
      expect(find.text(MoodCatalog.byId('cozy').kaomoji), findsNothing);
      // The rest of the card is untouched — mood label, devices, etc.
      expect(find.text(MoodCatalog.byId('cozy').label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the kaomoji with no art', (tester) async {
      await pumpCard(tester, const []);

      expect(find.byType(ArtSceneView), findsNothing);
      expect(find.text(MoodCatalog.byId('cozy').kaomoji), findsOneWidget);
    });
  });
}
