import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'app_navigator.dart';
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
      navigatorKey: kehaiNavigatorKey,
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Desktop hides the OS title bar (see DesktopWindowService), so every
      // screen — dialogs included — sits inside our own window chrome.
      // The chrome lives above the Navigator, i.e. above its Overlay — but
      // the titlebar's Tooltips need an Overlay ancestor, so give the chrome
      // one of its own.
      builder: (context, child) => DesktopWindowService.isSupported
          ? Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => _DesktopWindowChrome(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            )
          : child ?? const SizedBox.shrink(),
      home: const _RootSwitcher(),
    );
  }
}

/// Our replacement for the native frame, in both window states.
///
/// Expanded: the [KehaiTitleBar] strip, a 2px ink border so the undecorated
/// window still has an edge, and invisible drag-to-resize margins (a
/// frameless window has no resize borders of its own).
///
/// Mini: none of that. The little card paints its own frame, is not
/// resizable, and drags itself — so the chrome gets out of the way entirely
/// and lets [MiniPartnerWindow] fill the window.
class _DesktopWindowChrome extends StatelessWidget {
  const _DesktopWindowChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: DesktopWindowService.instance.windowMode,
      builder: (context, _) {
        if (DesktopWindowService.instance.windowMode.isMini) {
          // Forwards raw pointer-over-the-card presence to OledCare's idle
          // dimmer (kb/platform-desktop.md) — the mini window has no chrome
          // of its own, so [child] here IS the card, edge to edge, and this
          // MouseRegion sits directly around it rather than inside
          // MiniPartnerWindow itself.
          return MouseRegion(
            onEnter: (_) => DesktopWindowService.instance.oledCare.onHoverEnter(),
            onExit: (_) => DesktopWindowService.instance.oledCare.onHoverExit(),
            child: child,
          );
        }
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
      },
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
    // Onboarding needs room to type. If we somehow end up on one of those
    // screens while shrunk (logging out from the panel, say), grow back.
    if (controller.stage != AppStage.home &&
        DesktopWindowService.isSupported &&
        DesktopWindowService.instance.windowMode.isMini) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => DesktopWindowService.instance.windowMode.expand(),
      );
    }
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
