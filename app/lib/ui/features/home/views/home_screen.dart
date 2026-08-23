import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/countdowns_view_model.dart';
import '../view_models/home_view_model.dart';
import '../view_models/notes_view_model.dart';
import 'countdowns_window.dart';
import 'mood_picker.dart';
import 'notes_window.dart';
import 'partner_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _viewModel;
  late final CountdownsViewModel _countdownsViewModel;
  late final NotesViewModel _notesViewModel;
  final _noteController = TextEditingController();
  String _lastSyncedNote = '';

  @override
  void initState() {
    super.initState();
    final controller = AppScope.of(context, listen: false);
    _viewModel = HomeViewModel(
      authRepository: controller.authRepository!,
      coupleRepository: controller.coupleRepository!,
      statusRepository: controller.statusRepository!,
      deviceRepository: controller.deviceRepository!,
      heartbeatService: controller.heartbeatService!,
      deviceInfoService: controller.deviceInfoService,
      prefs: controller.prefs,
    );
    _viewModel.addListener(_syncNoteController);
    _viewModel.init();

    _countdownsViewModel = CountdownsViewModel(
      authRepository: controller.authRepository!,
      coupleRepository: controller.coupleRepository!,
      countdownRepository: controller.countdownRepository!,
    )..init();

    _notesViewModel = NotesViewModel(
      authRepository: controller.authRepository!,
      noteRepository: controller.noteRepository!,
    )..init();
  }

  void _syncNoteController() {
    if (_viewModel.myNote != _lastSyncedNote) {
      _lastSyncedNote = _viewModel.myNote;
      _noteController.text = _viewModel.myNote;
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncNoteController);
    _noteController.dispose();
    _viewModel.dispose();
    _countdownsViewModel.dispose();
    _notesViewModel.dispose();
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
            if (_viewModel.isLoading) {
              return Center(
                child: Text(AppStrings.loading, style: AppTextStyles.body1.copyWith(color: colors.ink)),
              );
            }
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
                              AppStrings.appName,
                              style: AppTextStyles.heading.copyWith(color: colors.ink),
                            ),
                          ),
                          PixelButton(
                            label: AppStrings.logOut,
                            onPressed: () => AppScope.of(context, listen: false).logOut(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_viewModel.hasPartner)
                        PartnerCard(
                          partnerName: _viewModel.partner!.name,
                          status: _viewModel.partnerStatus,
                          phoneOnline: _viewModel.partnerPhoneOnline,
                          desktopOnline: _viewModel.partnerDesktopOnline,
                          ambientLine: _viewModel.partnerAmbientLine,
                          batteryInfo: _viewModel.partnerBatteryInfo,
                        )
                      else
                        _WaitingForPartner(
                          inviteCode: _viewModel.inviteCode,
                          onRefresh: _viewModel.checkForPartner,
                        ),
                      const SizedBox(height: 20),
                      RetroWindow(
                        title: AppStrings.moodPickerTitle,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoodPicker(
                              selectedId: _viewModel.myMoodId,
                              onSelect: _viewModel.pickMood,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _noteController,
                              style: AppTextStyles.body1,
                              decoration: const InputDecoration(hintText: AppStrings.noteHint),
                              onChanged: (v) => _lastSyncedNote = v,
                              onSubmitted: _viewModel.updateNote,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: PixelButton(
                                primary: true,
                                label: AppStrings.saveNote,
                                onPressed: () => _viewModel.updateNote(_noteController.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ListenableBuilder(
                        listenable: _countdownsViewModel,
                        builder: (context, _) {
                          if (_countdownsViewModel.isLoading) return const SizedBox.shrink();
                          return CountdownsWindow(viewModel: _countdownsViewModel);
                        },
                      ),
                      const SizedBox(height: 20),
                      ListenableBuilder(
                        listenable: _notesViewModel,
                        builder: (context, _) {
                          if (_notesViewModel.isLoading) return const SizedBox.shrink();
                          return NotesWindow(viewModel: _notesViewModel);
                        },
                      ),
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

class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({required this.inviteCode, required this.onRefresh});

  final String? inviteCode;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RetroWindow(
      title: AppStrings.waitingTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Text(
              AppStrings.waitingKaomoji,
              style: AppTextStyles.kaomojiLarge.copyWith(color: colors.accent2),
            ),
          ),
          const SizedBox(height: 10),
          Text(AppStrings.waitingBody, style: AppTextStyles.body2, textAlign: TextAlign.center),
          if (inviteCode != null) ...[
            const SizedBox(height: 14),
            Text(AppStrings.inviteCodeShort, style: AppTextStyles.caption),
            const SizedBox(height: 6),
            BevelBox(
              color: colors.chrome,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  inviteCode!,
                  style: AppTextStyles.heading.copyWith(fontSize: 24, letterSpacing: 4, color: colors.ink),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PixelButton(
                  label: AppStrings.copyCode,
                  onPressed: () => Clipboard.setData(ClipboardData(text: inviteCode!)),
                ),
                const SizedBox(width: 10),
                PixelButton(primary: true, label: AppStrings.retry, onPressed: onRefresh),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            PixelButton(primary: true, label: AppStrings.retry, onPressed: onRefresh),
          ],
        ],
      ),
    );
  }
}
