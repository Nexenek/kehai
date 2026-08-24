import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/portal/portal_engine.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/portal/portal_call_screen.dart';

import 'support/pixel_fonts.dart';

/// A whole portal engine's worth of surface with no engine behind it —
/// exactly the point of [PortalCallSurface]. See portal_engine.dart's own
/// note on the interface for why the screen can be driven through every
/// state without repositories, a peer, or the native WebRTC plugin.
class _FakeSurface extends ChangeNotifier implements PortalCallSurface {
  _FakeSurface(this._state);

  PortalState _state;
  final calls = <String>[];

  @override
  PortalState get state => _state;

  @override
  String? lastError;

  @override
  String? partnerId;

  @override
  Null get localRenderer => null;

  @override
  Null get remoteRenderer => null;

  void moveTo(PortalState next) {
    _state = next;
    notifyListeners();
  }

  @override
  Future<void> knock() async => calls.add('knock');

  @override
  Future<void> accept() async => calls.add('accept');

  @override
  Future<void> decline() async => calls.add('decline');

  @override
  Future<void> hangUp() async => calls.add('hangUp');
}

Future<PrefsService> _fakePrefs() async {
  SharedPreferences.setMockInitialValues({});
  return PrefsService.create();
}

Offset _drapeOffset(WidgetTester tester, String key) => tester
    .widget<AnimatedSlide>(find.byKey(Key(key)))
    .offset;

Future<Widget> _host(
  PortalCallSurface engine, {
  bool Function()? partnerDark,
  bool disableAnimations = false,
}) async {
  final prefs = await _fakePrefs();
  return MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: PortalCallScreen(
          engine: engine,
          prefs: prefs,
          partnerDark: partnerDark ?? () => false,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadPixelFonts);

  testWidgets('idle offers the knock button, curtain closed', (tester) async {
    final surface = _FakeSurface(PortalState.idle);
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    expect(find.byKey(const Key('portal-knock-button')), findsOneWidget);
    expect(find.text(AppStrings.portalCurtainHint), findsOneWidget);
    expect(_drapeOffset(tester, 'portal-drape-left'), Offset.zero);
    expect(_drapeOffset(tester, 'portal-drape-right'), Offset.zero);

    await tester.tap(find.byKey(const Key('portal-knock-button')));
    await tester.pump();
    expect(surface.calls, ['knock']);
  });

  testWidgets('a dark partner window shows the dark-window line and dims '
      'the knock button, but still allows it', (tester) async {
    final surface = _FakeSurface(PortalState.idle);
    await tester.pumpWidget(await _host(surface, partnerDark: () => true));
    await tester.pump();

    expect(find.text(AppStrings.portalDarkWindow), findsOneWidget);
    expect(find.byKey(const Key('portal-knock-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('portal-knock-button')));
    await tester.pump();
    expect(surface.calls, ['knock']);
  });

  testWidgets('a last error shows over the idle curtain', (tester) async {
    final surface = _FakeSurface(PortalState.idle)
      ..lastError = AppStrings.portalNoAnswer;
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    expect(find.byKey(const Key('portal-error')), findsOneWidget);
    expect(find.text(AppStrings.portalNoAnswer), findsOneWidget);
  });

  testWidgets('knocking pulses and offers a way to cancel, curtain closed', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.knocking);
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    expect(find.text(AppStrings.portalKnocking), findsOneWidget);
    expect(_drapeOffset(tester, 'portal-drape-left'), Offset.zero);
    expect(_drapeOffset(tester, 'portal-drape-right'), Offset.zero);

    await tester.tap(find.byKey(const Key('portal-cancel-knock')));
    await tester.pump();
    expect(surface.calls, ['hangUp']);
  });

  testWidgets('a knock at the window offers yes and no, nothing else', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.knocked);
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    expect(find.text(AppStrings.portalKnockedTitle), findsOneWidget);
    expect(find.byKey(const Key('portal-accept')), findsOneWidget);
    expect(find.byKey(const Key('portal-decline')), findsOneWidget);
    expect(_drapeOffset(tester, 'portal-drape-left'), Offset.zero);

    await tester.tap(find.byKey(const Key('portal-decline')));
    await tester.pump();
    expect(surface.calls, ['decline']);
  });

  testWidgets('accepting calls accept', (tester) async {
    final surface = _FakeSurface(PortalState.knocked);
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    await tester.tap(find.byKey(const Key('portal-accept')));
    await tester.pump();
    expect(surface.calls, ['accept']);
  });

  testWidgets('connecting shows the opening line, curtain still closed', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.connecting);
    await tester.pumpWidget(await _host(surface));
    await tester.pump();

    expect(find.text(AppStrings.portalConnecting), findsOneWidget);
    expect(_drapeOffset(tester, 'portal-drape-left'), Offset.zero);
    expect(_drapeOffset(tester, 'portal-drape-right'), Offset.zero);
    // Nothing but the curtain and its own text — no knock/accept/decline
    // controls are showing while machinery is mid-handshake.
    expect(find.byKey(const Key('portal-knock-button')), findsNothing);
    expect(find.byKey(const Key('portal-accept')), findsNothing);
  });

  testWidgets('connected parts the drapes and offers hang up', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.connected);
    await tester.pumpWidget(await _host(surface, disableAnimations: true));
    await tester.pump();

    expect(_drapeOffset(tester, 'portal-drape-left'), const Offset(-1, 0));
    expect(_drapeOffset(tester, 'portal-drape-right'), const Offset(1, 0));
    expect(find.byKey(const Key('portal-hang-up')), findsOneWidget);
    // Nothing from the closed-curtain content leaks through once open.
    expect(find.byKey(const Key('portal-knock-button')), findsNothing);
    expect(find.text(AppStrings.portalCurtainHint), findsNothing);

    await tester.tap(find.byKey(const Key('portal-hang-up')));
    await tester.pump();
    expect(surface.calls, ['hangUp']);
  });

  testWidgets(
    'closing offers no buttons, and the curtain is already closed',
    (tester) async {
      final surface = _FakeSurface(PortalState.closing);
      await tester.pumpWidget(await _host(surface));
      await tester.pump();

      expect(find.byKey(const Key('portal-hang-up')), findsNothing);
      expect(find.byKey(const Key('portal-knock-button')), findsNothing);
      expect(find.byKey(const Key('portal-accept')), findsNothing);
      expect(_drapeOffset(tester, 'portal-drape-left'), Offset.zero);
      expect(_drapeOffset(tester, 'portal-drape-right'), Offset.zero);
    },
  );

  testWidgets(
    'the curtain stays closed in every state but connected',
    (tester) async {
      for (final state in [
        PortalState.idle,
        PortalState.knocking,
        PortalState.knocked,
        PortalState.connecting,
        PortalState.closing,
      ]) {
        final surface = _FakeSurface(state);
        await tester.pumpWidget(await _host(surface, disableAnimations: true));
        await tester.pump();
        expect(
          _drapeOffset(tester, 'portal-drape-left'),
          Offset.zero,
          reason: '$state',
        );
        expect(
          _drapeOffset(tester, 'portal-drape-right'),
          Offset.zero,
          reason: '$state',
        );
      }
    },
  );

  testWidgets('it rebuilds when the engine changes state', (tester) async {
    final surface = _FakeSurface(PortalState.idle);
    await tester.pumpWidget(await _host(surface, disableAnimations: true));
    await tester.pump();
    expect(find.byKey(const Key('portal-knock-button')), findsOneWidget);

    surface.moveTo(PortalState.knocked);
    await tester.pump();

    expect(find.byKey(const Key('portal-knock-button')), findsNothing);
    expect(find.byKey(const Key('portal-accept')), findsOneWidget);
  });

  testWidgets('reduced motion makes the drape parting instant', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.knocked);
    await tester.pumpWidget(await _host(surface, disableAnimations: true));
    await tester.pump();

    surface.moveTo(PortalState.connecting);
    await tester.pump();
    surface.moveTo(PortalState.connected);
    // No pumpAndSettle needed — Duration.zero means there's nothing left to
    // animate the very next frame.
    await tester.pump();

    expect(_drapeOffset(tester, 'portal-drape-left'), const Offset(-1, 0));
    expect(
      tester.widget<AnimatedSlide>(find.byKey(const Key('portal-drape-left'))).duration,
      Duration.zero,
    );
  });

  testWidgets('the back glyph pops the curtain route', (tester) async {
    final surface = _FakeSurface(PortalState.idle);
    final prefs = await _fakePrefs();
    await tester.pumpWidget(
      // disableAnimations sits ABOVE MaterialApp/Navigator on purpose: a
      // pushed route is a sibling page in the Navigator's Overlay, not a
      // descendant of whatever MediaQuery the *first* route wrapped itself
      // in, so it needs the override from further up to see it too. The
      // idle curtain's sway animation repeats forever by design — without
      // this, pumpAndSettle below would never settle.
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PortalCallScreen(engine: surface, prefs: prefs),
                    ),
                  ),
                  child: const Text('open portal'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open portal'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portal-knock-button')), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.back));
    await tester.pumpAndSettle();

    expect(find.text('open portal'), findsOneWidget);
    expect(find.byKey(const Key('portal-knock-button')), findsNothing);
  });

  testWidgets('the ✧ glyph opens the auto-accept settings dialog', (
    tester,
  ) async {
    final surface = _FakeSurface(PortalState.idle);
    await tester.pumpWidget(await _host(surface, disableAnimations: true));
    await tester.pump();

    await tester.tap(find.byTooltip(AppStrings.portalAutoAcceptTitle));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.portalAutoAcceptTitle), findsOneWidget);
    expect(find.text(AppStrings.portalAutoAcceptBody), findsOneWidget);
    expect(find.byKey(const Key('portal-auto-accept-toggle')), findsOneWidget);
  });
}
