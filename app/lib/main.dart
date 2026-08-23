import 'package:flutter/material.dart';

import 'app.dart';
import 'app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  controller.init();
  runApp(AppScope(controller: controller, child: const CouplesApp()));
}
