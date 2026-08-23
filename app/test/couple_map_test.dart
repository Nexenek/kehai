import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/location_point.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/core/widgets/pixel_heart_pin.dart';
import 'package:couples_app/ui/features/location/views/couple_map.dart';

import 'support/pixel_fonts.dart';

/// The map builds against the real tile layer; nothing here waits on an
/// actual tile, so no network is involved. What it does check is the parts
/// we own: a pin per person, the freshness chip, and OSM's attribution.
void main() {
  setUpAll(loadPixelFonts);

  LocationPoint point({
    required String userId,
    double lat = 52.2297,
    double lon = 21.0122,
    Duration age = Duration.zero,
  }) => LocationPoint(
    id: '$userId-point',
    userId: userId,
    lat: lat,
    lon: lon,
    recorded: DateTime.now().subtract(age),
  );

  Future<void> pumpMap(WidgetTester tester, List<MapPerson> people) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: CoupleMap(people: people)),
      ),
    );
    await tester.pump();
  }

  testWidgets('both of us get a pin, each with how old its fix is', (
    tester,
  ) async {
    await pumpMap(tester, [
      MapPerson(
        name: AppStrings.locationYou,
        isMe: true,
        point: point(userId: 'me'),
      ),
      MapPerson(
        name: 'mati',
        isMe: false,
        point: point(
          userId: 'them',
          lat: 50.0647,
          lon: 19.9450,
          age: const Duration(minutes: 12),
        ),
      ),
    ]);

    expect(find.byKey(const Key('couple-map')), findsOneWidget);
    expect(find.byType(PixelHeartPin), findsNWidgets(2));
    expect(find.text('you · just now'), findsOneWidget);
    expect(find.text('mati · 12m ago'), findsOneWidget);
  });

  testWidgets("OSM's attribution is on screen, per their tile policy", (
    tester,
  ) async {
    await pumpMap(tester, [
      MapPerson(
        name: AppStrings.locationYou,
        isMe: true,
        point: point(userId: 'me'),
      ),
    ]);

    expect(find.text(AppStrings.mapAttribution), findsOneWidget);
  });

  testWidgets('one person alone gets one pin and no crash', (tester) async {
    await pumpMap(tester, [
      const MapPerson(name: 'mati', isMe: false, point: null),
      MapPerson(
        name: AppStrings.locationYou,
        isMe: true,
        point: point(userId: 'me'),
      ),
    ]);

    expect(find.byType(PixelHeartPin), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tile layer identifies us to OSM by package name', (
    tester,
  ) async {
    await pumpMap(tester, [
      MapPerson(
        name: AppStrings.locationYou,
        isMe: true,
        point: point(userId: 'me'),
      ),
    ]);

    final tiles = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tiles.urlTemplate, CoupleMap.osmTileUrl);
    // flutter_map turns this into `flutter_map (app.kehai)`; a generic UA
    // is explicitly against the OSM tile usage policy.
    expect(
      tiles.tileProvider.headers['User-Agent'],
      contains(CoupleMap.userAgentPackageName),
    );
  });

  testWidgets('the recentre button only appears once you have panned away', (
    tester,
  ) async {
    await pumpMap(tester, [
      MapPerson(
        name: AppStrings.locationYou,
        isMe: true,
        point: point(userId: 'me'),
      ),
    ]);

    expect(find.byKey(const Key('map-recenter')), findsNothing);
  });

  test('the "as of" chip reads as one phrase', () {
    expect(AppStrings.locationAsOf('you', 'just now'), 'you · just now');
    expect(AppStrings.locationAsOf('mati', '2h ago'), 'mati · 2h ago');
  });
}
