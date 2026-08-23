import 'package:flutter/material.dart';

import 'app.dart';
import 'app_controller.dart';
import 'data/services/background/kehai_foreground_task.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android only: sets up the port the foreground service's background
  // isolate talks back on, and registers the notification channel/task
  // options. No-op everywhere else.
  KehaiForegroundTask.bootstrap();
  final controller = AppController();
  controller.init();
  runApp(AppScope(controller: controller, child: const CouplesApp()));
}
