import 'package:flutter/material.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/phone_superpowers_view_model.dart';
import 'sound_settings_dialog.dart';

/// The Android permissions screen, in the retro-window vocabulary the rest
/// of the app uses. One window per capability: what it unlocks, what it
/// honestly costs, current status, and a button.
///
/// Deliberately *not* an onboarding gate — a couples app that opens with
/// four permission dialogs is a couples app you close. It's reachable from
/// home whenever the user is curious, and every row degrades to "fine,
/// then that signal stays off".
class PhoneSuperpowersScreen extends StatefulWidget {
  const PhoneSuperpowersScreen({super.key});

  @override
  State<PhoneSuperpowersScreen> createState() => _PhoneSuperpowersScreenState();
}

class _PhoneSuperpowersScreenState extends State<PhoneSuperpowersScreen>
    with WidgetsBindingObserver {
  late final PhoneSuperpowersViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    final controller = AppScope.of(context, listen: false);
    _viewModel = PhoneSuperpowersViewModel(
      initialShareFocusedApp: controller.shareFocusedApp,
      initialShareUnknownApps: controller.shareUnknownApps,
      initialShareLocation: controller.shareLocation,
      onSetShareFocusedApp: controller.setShareFocusedApp,
      onSetShareUnknownApps: controller.setShareUnknownApps,
      onSetShareLocation: controller.setShareLocation,
    );
    WidgetsBinding.instance.addObserver(this);
    _viewModel.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The battery and notification-listener grants both happen in system
    // UI, so the only reliable moment to re-read them is when the user
    // lands back here.
    if (state == AppLifecycleState.resumed) _viewModel.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStrings.superpowersTitle,
                              style: AppTextStyles.heading.copyWith(
                                color: colors.ink,
                              ),
                            ),
                          ),
                          PixelButton(
                            label: AppStrings.superpowersDone,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppStrings.superpowersIntro,
                        style: AppTextStyles.body2.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 18),
                      if (!_viewModel.isSupported)
                        const _Unsupported()
                      else ...[
                        _SuperpowerWindow(
                          title: AppStrings.superpowerNotificationsTitle,
                          body: AppStrings.superpowerNotificationsBody,
                          granted: _viewModel.notificationsGranted,
                          actionLabel: AppStrings.superpowersGrant,
                          onAction: _viewModel.requestNotifications,
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.superpowerBatteryTitle,
                          body: AppStrings.superpowerBatteryBody,
                          granted: _viewModel.batteryExempt,
                          actionLabel: AppStrings.superpowersGrant,
                          onAction: _viewModel.requestBatteryExemption,
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.superpowerListenerTitle,
                          body: AppStrings.superpowerListenerBody,
                          granted: _viewModel.listenerEnabled,
                          actionLabel: AppStrings.superpowersGrant,
                          onAction: _viewModel.openListenerSettings,
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.superpowerServiceTitle,
                          body: AppStrings.superpowerServiceBody,
                          granted: _viewModel.serviceRunning,
                          grantedLabel: AppStrings.superpowerServiceRunning,
                          pendingLabel: AppStrings.superpowerServiceStopped,
                          actionLabel: _viewModel.serviceRunning
                              ? AppStrings.superpowerServiceStop
                              : AppStrings.superpowerServiceStart,
                          // The only row whose action stays live once
                          // granted — stopping the helper is a thing the
                          // user is allowed to want.
                          alwaysActionable: true,
                          onAction: _viewModel.toggleService,
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.superpowerUsageAccessTitle,
                          body: AppStrings.superpowerUsageAccessBody,
                          granted: _viewModel.usageAccessGranted,
                          actionLabel: AppStrings.superpowersGrant,
                          onAction: _viewModel.openUsageAccessSettings,
                        ),
                        const SizedBox(height: 16),
                        // The honest two-step location flow: "granted"
                        // means the full "all the time" grant, and while
                        // only "while using" is held the status/action pair
                        // walks the user to the second step instead of
                        // claiming they're done.
                        _SuperpowerWindow(
                          title: AppStrings.superpowerLocationPermissionTitle,
                          body: AppStrings.superpowerLocationPermissionBody,
                          granted: _viewModel.locationAlwaysGranted,
                          pendingLabel: _viewModel.locationWhileInUseGranted
                              ? AppStrings
                                    .superpowerLocationPermissionWhileInUseOnly
                              : AppStrings.superpowerLocationPermissionOff,
                          actionLabel: _viewModel.locationWhileInUseGranted
                              ? AppStrings.superpowerLocationGrantAlways
                              : AppStrings.superpowerLocationGrantWhileInUse,
                          onAction: _viewModel.locationWhileInUseGranted
                              ? _viewModel.openLocationAlwaysSettings
                              : _viewModel.requestLocationWhileInUse,
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.shareFocusedAppTitle,
                          body: AppStrings.shareFocusedAppBody,
                          granted: _viewModel.shareFocusedApp,
                          grantedLabel: AppStrings.shareFocusedAppOn,
                          pendingLabel: AppStrings.shareFocusedAppOff,
                          actionLabel: _viewModel.shareFocusedApp
                              ? AppStrings.shareFocusedAppTurnOff
                              : AppStrings.shareFocusedAppTurnOn,
                          // A plain on/off preference, not a one-way OS
                          // grant — the action stays live either way so the
                          // user can flip it straight back off.
                          alwaysActionable: true,
                          // "What we'd share right now" — refreshed every
                          // ~3s by the view model, so a silent failure (no
                          // Usage Access grant, an unmapped app) is visible
                          // instead of the partner's card just never saying
                          // anything (kb/features.md "Focused-app status").
                          preview: _viewModel.activityPreview,
                          onAction: () => _viewModel.setShareFocusedApp(
                            !_viewModel.shareFocusedApp,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.shareUnknownAppsTitle,
                          body: AppStrings.shareUnknownAppsBody,
                          granted: _viewModel.shareUnknownApps,
                          grantedLabel: AppStrings.shareFocusedAppOn,
                          pendingLabel: AppStrings.shareFocusedAppOff,
                          actionLabel: _viewModel.shareUnknownApps
                              ? AppStrings.shareFocusedAppTurnOff
                              : AppStrings.shareFocusedAppTurnOn,
                          alwaysActionable: true,
                          onAction: () => _viewModel.setShareUnknownApps(
                            !_viewModel.shareUnknownApps,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SuperpowerWindow(
                          title: AppStrings.shareLocationTitle,
                          body: AppStrings.shareLocationBody,
                          granted: _viewModel.shareLocation,
                          grantedLabel: AppStrings.shareFocusedAppOn,
                          pendingLabel: AppStrings.shareFocusedAppOff,
                          actionLabel: _viewModel.shareLocation
                              ? AppStrings.shareFocusedAppTurnOff
                              : AppStrings.shareFocusedAppTurnOn,
                          alwaysActionable: true,
                          onAction: () => _viewModel.setShareLocation(
                            !_viewModel.shareLocation,
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Android's way in to the "sounds ♪" window — the
                        // desktop reaches it from the ✧ title-bar window
                        // instead (see showSoundSettingsDialog's doc
                        // comment on why it's its own window either way).
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PixelButton(
                            key: const Key('superpowers-open-sounds'),
                            label: AppStrings.soundsOpen,
                            onPressed: () => showSoundSettingsDialog(
                              context,
                              notifier: AppScope.of(
                                context,
                                listen: false,
                              ).notifier,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PixelButton(
                            label: AppStrings.superpowersRefresh,
                            onPressed: _viewModel.refresh,
                          ),
                        ),
                      ],
                      if (_viewModel.message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _viewModel.message!,
                          style: AppTextStyles.body2.copyWith(
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuperpowerWindow extends StatelessWidget {
  const _SuperpowerWindow({
    required this.title,
    required this.body,
    required this.granted,
    required this.actionLabel,
    required this.onAction,
    this.grantedLabel,
    this.pendingLabel,
    this.alwaysActionable = false,
    this.preview,
  });

  final String title;
  final String body;
  final bool granted;
  final String actionLabel;
  final VoidCallback onAction;
  final String? grantedLabel;
  final String? pendingLabel;
  final bool alwaysActionable;

  /// "What we'd share right now" (kb/features.md "Focused-app status") —
  /// only the `shareFocusedApp` window passes this; every other window
  /// leaves it null and skips the line entirely.
  final String? preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusText = granted
        ? (grantedLabel ?? AppStrings.superpowersGranted)
        : (pendingLabel ?? '');

    return RetroWindow(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body, style: AppTextStyles.body2.copyWith(color: colors.ink)),
          if (preview != null && preview!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview!,
              key: const Key('superpower-activity-preview'),
              style: AppTextStyles.caption.copyWith(color: colors.accent),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (statusText.isNotEmpty)
                BevelBox(
                  color: granted ? colors.mint : colors.chromeAlt,
                  style: BevelStyle.sunken,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    statusText,
                    style: AppTextStyles.caption.copyWith(color: colors.ink),
                  ),
                ),
              const Spacer(),
              if (!granted || alwaysActionable)
                PixelButton(
                  primary: !granted,
                  label: actionLabel,
                  onPressed: onAction,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported();

  @override
  Widget build(BuildContext context) {
    return RetroWindow(
      title: AppStrings.superpowersTitle,
      child: Text(
        AppStrings.superpowersUnavailable,
        style: AppTextStyles.body2.copyWith(color: context.colors.ink),
      ),
    );
  }
}
