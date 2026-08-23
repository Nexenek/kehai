import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/models/device_status.dart';
import 'package:couples_app/domain/models/utc_offset.dart';
import 'package:couples_app/domain/models/ping.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/home/views/partner_card.dart';

/// A different-timezone offset than whatever this test machine's own
/// `UtcOffset.now()` happens to resolve to — computed relative to it
/// (rather than hard-coded) so the test is deterministic on any CI
/// machine's local timezone.
UtcOffset _differentOffsetThanMine() {
  final mine = UtcOffset.now().minutes;
  // Wrap into a plausible (-12h..+14h) range after the shift.
  var shifted = mine + 120;
  if (shifted > 14 * 60) shifted -= 24 * 60;
  return UtcOffset(shifted);
}

void main() {
  testWidgets('shows no dual-clock line with no partner devices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PartnerCard(
            partnerName: 'mati',
            status: null,
            phoneOnline: false,
            desktopOnline: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('partner-dual-clock-line')), findsNothing);
  });

  testWidgets(
    'shows the dual-clock line when the partner is in a different offset',
    (tester) async {
      final theirs = _differentOffsetThanMine();
      final device = DeviceStatus(
        id: 'd1',
        ownerId: 'partner',
        name: 'phone',
        kind: 'phone',
        lastSeen: DateTime.now(),
        timezone: theirs.encode(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PartnerCard(
              partnerName: 'mati',
              status: null,
              phoneOnline: true,
              desktopOnline: false,
              partnerDevices: [device],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('partner-dual-clock-line')), findsOneWidget);
      final text = tester.widget<Text>(
        find.byKey(const Key('partner-dual-clock-line')),
      );
      expect(text.data, contains('their time:'));
    },
  );

  testWidgets(
    'shows no dual-clock line when the partner is in my own offset',
    (tester) async {
      final device = DeviceStatus(
        id: 'd1',
        ownerId: 'partner',
        name: 'phone',
        kind: 'phone',
        lastSeen: DateTime.now(),
        timezone: UtcOffset.now().encode(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PartnerCard(
              partnerName: 'mati',
              status: null,
              phoneOnline: true,
              desktopOnline: false,
              partnerDevices: [device],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('partner-dual-clock-line')), findsNothing);
    },
  );

  group('ping affordances', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      void Function(PingKind)? onSendPing,
      bool canSendPing = true,
      bool pingJustSent = false,
      Ping? receivedPing,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PartnerCard(
              partnerName: 'mati',
              status: null,
              phoneOnline: true,
              desktopOnline: false,
              onSendPing: onSendPing,
              canSendPing: canSendPing,
              pingJustSent: pingJustSent,
              receivedPing: receivedPing,
            ),
          ),
        ),
      ),
    );

    testWidgets('no button at all without a send callback', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('ping-send-button')), findsNothing);
    });

    testWidgets('the button sends "thinking" on one tap', (tester) async {
      final sent = <PingKind>[];
      await pumpCard(tester, onSendPing: sent.add);

      await tester.tap(find.byKey(const Key('ping-send-button')));
      await tester.pump();
      expect(sent, [PingKind.thinking]);
    });

    testWidgets('the flourish shows while a send is fresh', (tester) async {
      await pumpCard(tester, onSendPing: (_) {}, pingJustSent: true);
      expect(find.text(AppStrings.pingSentLabel), findsOneWidget);
    });

    testWidgets('a received ping shows one quiet line', (tester) async {
      await pumpCard(
        tester,
        onSendPing: (_) {},
        receivedPing: Ping(
          id: 'p1',
          coupleId: 'c1',
          fromId: 'them',
          kind: PingKind.hug,
          created: DateTime.now(),
        ),
      );

      expect(find.byKey(const Key('partner-received-ping')), findsOneWidget);
      expect(
        find.text(AppStrings.pingReceivedLine(PingKind.hug)),
        findsOneWidget,
      );
    });

    testWidgets('no received line when nothing has landed', (tester) async {
      await pumpCard(tester, onSendPing: (_) {});
      expect(find.byKey(const Key('partner-received-ping')), findsNothing);
    });
  });
}
