import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/notifications/kehai_notifier.dart';
import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/settings/views/sound_settings_dialog.dart';

import 'support/pixel_fonts.dart';

void main() {
  setUpAll(loadPixelFonts);

  /// `supportedOverride: false` keeps the platform plugin out of a widget
  /// test — the picker's persistence and rendering are what's under test,
  /// and both are platform-free.
  Future<KehaiNotifier> notifier() async => KehaiNotifier(
    prefs: await PrefsService.create(),
    supportedOverride: false,
  );

  Future<KehaiNotifier> pumpWindow(WidgetTester tester) async {
    final n = await notifier();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: SoundSettingsContent(notifier: n)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return n;
  }

  testWidgets('offers all five choices for all four events', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWindow(tester);

    for (final kind in KehaiEventKind.values) {
      expect(find.text(AppStrings.soundsEventLabel(kind)), findsOneWidget);
      for (final sound in KehaiSound.pickable) {
        expect(
          find.byKey(Key('sound-${kind.id}-${sound.id}')),
          findsOneWidget,
          reason: '${kind.id} should offer ${sound.id}',
        );
      }
    }
  });

  testWidgets('picking a sound persists it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final n = await pumpWindow(tester);
    expect(n.soundFor(KehaiEventKind.doodle), KehaiSound.pop);

    await tester.tap(find.byKey(const Key('sound-doodle-purr')));
    await tester.pumpAndSettle();

    expect(n.soundFor(KehaiEventKind.doodle), KehaiSound.purr);
    // …and it survives a fresh notifier reading the same prefs.
    expect((await notifier()).soundFor(KehaiEventKind.doodle), KehaiSound.purr);
  });

  testWidgets('a saved choice is what the window opens on', (tester) async {
    SharedPreferences.setMockInitialValues({
      'notification_sound_ping': 'chime',
    });
    final n = await pumpWindow(tester);
    expect(n.soundFor(KehaiEventKind.ping), KehaiSound.chime);
  });

  testWidgets('silence is pickable', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final n = await pumpWindow(tester);

    await tester.tap(find.byKey(const Key('sound-reveal-silent')));
    await tester.pumpAndSettle();

    expect(n.soundFor(KehaiEventKind.reveal).isSilent, isTrue);
  });

  testWidgets('says out loud why moods are not on the list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWindow(tester);
    expect(find.byKey(const Key('sounds-ambient-note')), findsOneWidget);
  });
}
