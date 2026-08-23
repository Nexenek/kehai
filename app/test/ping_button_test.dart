import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/ping.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/pings/ping_button.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('ThinkingOfYouButton', () {
    testWidgets('one tap sends the default kind, no menu in the way', (
      tester,
    ) async {
      final sent = <PingKind>[];
      await tester.pumpWidget(
        _host(ThinkingOfYouButton(onSend: sent.add)),
      );

      expect(find.text(AppStrings.pingButtonLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('ping-send-button')));
      await tester.pump();

      expect(sent, [PingKind.thinking]);
    });

    testWidgets('the debounce greys it out rather than eating taps', (
      tester,
    ) async {
      final sent = <PingKind>[];
      await tester.pumpWidget(
        _host(ThinkingOfYouButton(onSend: sent.add, canSend: false)),
      );

      await tester.tap(
        find.byKey(const Key('ping-send-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('the flourish replaces the label and blocks a re-send', (
      tester,
    ) async {
      final sent = <PingKind>[];
      await tester.pumpWidget(
        _host(ThinkingOfYouButton(onSend: sent.add, justSent: true)),
      );

      expect(find.text(AppStrings.pingSentLabel), findsOneWidget);
      expect(find.text(AppStrings.pingButtonLabel), findsNothing);

      await tester.tap(
        find.byKey(const Key('ping-send-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('the ▾ opens the picker and each kind sends itself', (
      tester,
    ) async {
      for (final kind in PingKind.values) {
        final sent = <PingKind>[];
        await tester.pumpWidget(
          _host(ThinkingOfYouButton(onSend: sent.add)),
        );

        await tester.tap(find.byKey(const Key('ping-kind-affordance')));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.pingKindPickerTitle), findsOneWidget);

        await tester.tap(find.byKey(Key('ping-kind-${kind.id}')));
        await tester.pumpAndSettle();

        expect(sent, [kind], reason: 'picking ${kind.id}');
      }
    });

    testWidgets('long-pressing the button opens the same picker', (
      tester,
    ) async {
      final sent = <PingKind>[];
      await tester.pumpWidget(_host(ThinkingOfYouButton(onSend: sent.add)));

      await tester.longPress(find.byKey(const Key('ping-send-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ping-kind-hug')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ping-kind-hug')));
      await tester.pumpAndSettle();
      expect(sent, [PingKind.hug]);
    });

    testWidgets('dismissing the picker sends nothing', (tester) async {
      final sent = <PingKind>[];
      await tester.pumpWidget(_host(ThinkingOfYouButton(onSend: sent.add)));

      await tester.tap(find.byKey(const Key('ping-kind-affordance')));
      await tester.pumpAndSettle();
      // Tap the barrier, outside the little window.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      expect(find.text(AppStrings.pingKindPickerTitle), findsNothing);
    });

    testWidgets('every kind shows its kaomoji in the picker', (tester) async {
      await tester.pumpWidget(_host(ThinkingOfYouButton(onSend: (_) {})));
      await tester.tap(find.byKey(const Key('ping-kind-affordance')));
      await tester.pumpAndSettle();

      for (final kind in PingKind.values) {
        expect(find.text(kind.kaomoji), findsOneWidget);
        expect(find.text(kind.label), findsOneWidget);
      }
    });
  });

  group('MiniPingHeart', () {
    testWidgets('tapping it sends', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(MiniPingHeart(onSend: () => taps++)));

      await tester.tap(find.byKey(const Key('mini-ping-heart')));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('it is inert during the debounce and the flourish', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(MiniPingHeart(onSend: () => taps++, canSend: false)),
      );
      await tester.tap(find.byKey(const Key('mini-ping-heart')));
      await tester.pump();
      expect(taps, 0);

      await tester.pumpWidget(
        _host(MiniPingHeart(onSend: () => taps++, justSent: true)),
      );
      await tester.tap(find.byKey(const Key('mini-ping-heart')));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('its tap target does not fall through to the card', (
      tester,
    ) async {
      // The heart lives on top of the mini card, whose whole surface expands
      // the window — a ping must never also open the panel.
      var pinged = 0;
      var expanded = 0;
      await tester.pumpWidget(
        _host(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => expanded++,
            child: Center(child: MiniPingHeart(onSend: () => pinged++)),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('mini-ping-heart')));
      await tester.pump();
      expect(pinged, 1);
      expect(expanded, 0);
    });
  });
}
