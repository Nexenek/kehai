import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/desktop_window_service.dart';

/// [DesktopWindowService.setMiniTransparency] round-trips through
/// `app.kehai/window#setTransparent` — the channel windows/runner and
/// linux/runner answer natively (transparency_channel.cpp,
/// my_application.cc). These tests exercise just that round-trip with a
/// mocked channel, without touching the real window_manager binding that
/// [applyMini]/[applyExpanded] also need (which isn't available under
/// `flutter test`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.kehai/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    DesktopWindowService.debugIsSupported = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('off desktop, the channel is never touched and it reports false', () async {
    DesktopWindowService.debugIsSupported = false;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return true;
    });

    final result = await DesktopWindowService.instance.setMiniTransparency(
      true,
    );

    expect(result, isFalse);
    expect(called, isFalse);
  });

  test('relays the runner\'s capability answer for "on"', () async {
    DesktopWindowService.debugIsSupported = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setTransparent');
      expect(call.arguments, true);
      return true;
    });

    expect(
      await DesktopWindowService.instance.setMiniTransparency(true),
      isTrue,
    );
  });

  test('a runner that cannot manage it reports false, not an exception', () async {
    DesktopWindowService.debugIsSupported = true;
    messenger.setMockMethodCallHandler(channel, (call) async => false);

    expect(
      await DesktopWindowService.instance.setMiniTransparency(true),
      isFalse,
    );
  });

  test('a missing runner channel degrades to false, never crashes', () async {
    DesktopWindowService.debugIsSupported = true;
    // No handler registered at all — invokeMethod throws
    // MissingPluginException, exactly like a build without the native side.
    messenger.setMockMethodCallHandler(channel, null);

    expect(
      await DesktopWindowService.instance.setMiniTransparency(true),
      isFalse,
    );
  });

  test('asking for "off" passes false through to the runner', () async {
    DesktopWindowService.debugIsSupported = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, false);
      return true;
    });

    await DesktopWindowService.instance.setMiniTransparency(false);
  });
}
