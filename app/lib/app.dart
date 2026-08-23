import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/core/strings/app_strings.dart';
import 'ui/core/theme/app_theme.dart';
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
      home: const _RootSwitcher(),
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
