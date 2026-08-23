import 'package:flutter/widgets.dart';

/// The app's one Navigator, reachable from OUTSIDE the Navigator subtree.
///
/// The desktop window chrome (titlebar) is installed via `MaterialApp.builder`
/// and therefore sits ABOVE the Navigator — `showDialog` from a chrome
/// context finds no Navigator and silently does nothing (shipped bug: the
/// ✧ sharing button was dead on desktop). Chrome code opens dialogs through
/// this key's context instead. Lives in its own file so the titlebar doesn't
/// have to import app.dart (which imports the titlebar back).
final GlobalKey<NavigatorState> kehaiNavigatorKey = GlobalKey<NavigatorState>();
