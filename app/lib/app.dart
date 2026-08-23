import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'data/services/desktop_window_service.dart';
import 'ui/core/strings/app_strings.dart';
import 'ui/core/theme/app_colors.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/widgets/kehai_title_bar.dart';
import 'ui/features/home/views/home_screen.dart';
import 'ui/features/onboarding/views/auth_screen.dart';
import 'ui/features/onboarding/views/couple_setup_screen.dart';
import 'ui/features/onboarding/views/server_url_screen.dart';

class CouplesApp extends StatelessWidget {
  const CouplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Desktop hides the OS title bar (see DesktopWindowService), so every
      // screen — dialogs included — sits inside our own window chrome.
      builder: (context, child) => DesktopWindowService.isSupported
          ? _DesktopWindowChrome(child: child ?? const SizedBox.shrink())
          : child ?? const SizedBox.shrink(),
      home: const _RootSwitcher(),
    );
  }
}

/// Our replacement for the native frame: the [KehaiTitleBar] strip, a 2px ink
/// border so the undecorated window still has an edge, and invisible
/// drag-to-resize margins (a frameless window has no resize borders of its
/// own).
class _DesktopWindowChrome extends StatelessWidget {
  const _DesktopWindowChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragToResizeArea(
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(color: colors.ink, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KehaiTitleBar(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Swaps screens based on [AppController.stage]. Deliberately not a real
/// router — see the comment on [AppStage].
class _RootSwitcher extends StatelessWidget {
  const _RootSwitcher();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return switch (controller.stage) {
      AppStage.loading => const _LoadingScreen(),
      AppStage.serverSetup => const ServerUrlScreen(),
      AppStage.auth => const AuthScreen(),
      AppStage.coupleSetup => const CoupleSetupScreen(),
      AppStage.home => const HomeScreen(),
    };
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text(AppStrings.loading)));
  }
}
