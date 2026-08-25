import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_controller.dart';
import 'data/services/autostart_service.dart';
import 'data/services/background/kehai_foreground_task.dart';
import 'data/services/desktop_window_service.dart';
import 'data/services/kehai_tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android only: sets up the port the foreground service's background
  // isolate talks back on, and registers the notification channel/task
  // options. No-op everywhere else.
  KehaiForegroundTask.bootstrap();
  // Windows/Linux only, cheap and synchronous: points the "start with the
  // computer" backend (tray menu checkbox, KehaiTray) at this process's own
  // executable. Nothing is written to the registry/disk until the user
  // actually flips the checkbox.
  AutostartService.instance.bootstrap();
  // Windows/Linux only: sizes and docks the companion window (and restores
  // where the user left it) before the first frame, so it never flashes at
  // the default 1280×720. No-op on Android.
  await DesktopWindowService.instance.bootstrap();
  // The pixel heart in the tray — the handle you summon the window with, and
  // the only place that can end the app.
  await KehaiTray.instance.bootstrap(DesktopWindowService.instance.windowMode);

  final controller = AppController();
  // The tray is up before the composition root exists, so its "update to
  // vX.Y.Z" / "check for updates" entries are wired in afterwards. No-op off
  // Windows/Linux, where the tray never bootstrapped.
  KehaiTray.instance.attachUpdates(controller.updates);
  // Show the panel while we work out where we stand, then tuck into the
  // little window if there's actually a partner to watch over. Onboarding
  // stays big — nobody types a server address into a 240×150 card.
  unawaited(
    controller.init().then(
      (_) => DesktopWindowService.instance.settleInitialMode(
        paired: controller.stage == AppStage.home,
      ),
    ),
  );
  runApp(AppScope(controller: controller, child: const CouplesApp()));
}
