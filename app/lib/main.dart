import 'package:flutter/material.dart';

import 'app.dart';
import 'app_controller.dart';
import 'data/services/background/kehai_foreground_task.dart';
import 'data/services/desktop_window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android only: sets up the port the foreground service's background
  // isolate talks back on, and registers the notification channel/task
  // options. No-op everywhere else.
  KehaiForegroundTask.bootstrap();
  // Windows/Linux only: sizes and docks the companion window (and restores
  // where the user left it) before the first frame, so it never flashes at
  // the default 1280×720. No-op on Android.
  await DesktopWindowService.instance.bootstrap();
  final controller = AppController();
  controller.init();
  runApp(AppScope(controller: controller, child: const CouplesApp()));
}
