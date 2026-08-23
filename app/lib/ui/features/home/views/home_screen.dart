import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_controller.dart';
import '../../../../data/services/background/kehai_foreground_task.dart';
import '../../../../data/services/desktop_window_service.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../../doodle/doodle_canvas_dialog.dart';
import '../../instants/instants_view_model.dart';
import '../../instants/instants_window.dart';
import '../../location/view_models/location_view_model.dart';
import '../../location/views/location_window.dart';
import '../../settings/views/phone_superpowers_screen.dart';
import '../view_models/countdowns_view_model.dart';
import '../view_models/doodle_view_model.dart';
import '../view_models/home_view_model.dart';
import '../view_models/notes_view_model.dart';
import 'countdowns_window.dart';
import 'home_layout.dart';
import 'mini_partner_window.dart';
import 'my_mood_window.dart';
import 'notes_window.dart';
import 'partner_card.dart';

/// Owns the home view models and hands the pieces to [HomeBody], which picks
/// the shape for the space available (phone column / desktop companion pane /
/// wide "our desktop" spread — see [HomeLayoutMode]).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeViewModel _viewModel;
  late final CountdownsViewModel _countdownsViewModel;
  late final NotesViewModel _notesViewModel;
  late final DoodleViewModel _doodleViewModel;
  late final LocationViewModel _locationViewModel;
  late final InstantsViewModel _instantsViewModel;
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
      handOffPresenceToBackground: controller.handOffPresenceToBackground,
    );
    _viewModel.addListener(_syncFromHomeViewModel);
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

    _doodleViewModel = DoodleViewModel(
      authRepository: controller.authRepository!,
      doodleRepository: controller.doodleRepository!,
    )..init();

    _locationViewModel = LocationViewModel(
      authRepository: controller.authRepository!,
      locationRepository: controller.locationRepository!,
    )..init();

    _instantsViewModel = InstantsViewModel(
      authRepository: controller.authRepository!,
      instantRepository: controller.instantRepository!,
    )..init();
  }

  void _syncFromHomeViewModel() {
    if (_viewModel.myNote != _lastSyncedNote) {
      _lastSyncedNote = _viewModel.myNote;
      _noteController.text = _viewModel.myNote;
    }
    _doodleViewModel.updatePartner(_viewModel.partner?.id);
    // The partner's record carries their `ghost_until` along with their
    // name, so this hands over both at once.
    _locationViewModel.updatePartner(_viewModel.partner);
  }

  Future<void> _openDoodleCanvas() {
    return showDoodleCanvasDialog(context, onSend: _doodleViewModel.send);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_syncFromHomeViewModel);
    _noteController.dispose();
    _viewModel.dispose();
    _countdownsViewModel.dispose();
    _notesViewModel.dispose();
    _doodleViewModel.dispose();
    _locationViewModel.dispose();
    _instantsViewModel.dispose();
    super.dispose();
  }

  /// Each section keeps its own [ListenableBuilder] so a change in one
  /// window doesn't rebuild the others — and so a drawer opening doesn't
  /// rebuild anything but the drawer.
  HomeSections _buildSections(BuildContext context) {
    return HomeSections(
      partner: _viewModel.hasPartner
          ? PartnerCard(
              partnerName: _viewModel.partner!.name,
              status: _viewModel.partnerStatus,
              phoneOnline: _viewModel.partnerPhoneOnline,
              desktopOnline: _viewModel.partnerDesktopOnline,
              ambientLine: _viewModel.partnerAmbientLine,
              batteryInfo: _viewModel.partnerBatteryInfo,
              distanceLine: _locationViewModel.distanceLine,
              partnerDoodle: _doodleViewModel.partnerDoodle,
              onSendDoodle: _openDoodleCanvas,
            )
          : _WaitingForPartner(
              inviteCode: _viewModel.inviteCode,
              onRefresh: _viewModel.checkForPartner,
            ),
      mood: (context, onClose) => MyMoodWindow(
        selectedMoodId: _viewModel.myMoodId,
        onSelectMood: _viewModel.pickMood,
        noteController: _noteController,
        onNoteChanged: (v) => _lastSyncedNote = v,
        onSaveNote: _viewModel.updateNote,
        myDoodle: _doodleViewModel.myDoodle,
        onDeleteDoodle: _doodleViewModel.deleteMine,
        onClose: onClose,
      ),
      countdowns: (context, onClose) => ListenableBuilder(
        listenable: _countdownsViewModel,
        builder: (context, _) {
          if (_countdownsViewModel.isLoading) return const SizedBox.shrink();
          return CountdownsWindow(
            viewModel: _countdownsViewModel,
            onClose: onClose,
          );
        },
      ),
      notes: (context, onClose) => ListenableBuilder(
        listenable: _notesViewModel,
        builder: (context, _) {
          if (_notesViewModel.isLoading) return const SizedBox.shrink();
          return NotesWindow(viewModel: _notesViewModel, onClose: onClose);
        },
      ),
      instants: (context, onClose) => ListenableBuilder(
        listenable: _instantsViewModel,
        builder: (context, _) => InstantsWindow(
          viewModel: _instantsViewModel,
          onClose: onClose,
        ),
      ),
      map: (context, onClose) => ListenableBuilder(
        listenable: _locationViewModel,
        builder: (context, _) {
          if (_locationViewModel.isLoading) return const SizedBox.shrink();
          return LocationWindow(
            partnerName: _viewModel.partner?.name ?? '',
            myPoint: _locationViewModel.myPoint,
            partnerPoint: _locationViewModel.partnerPoint,
            myGhost: _locationViewModel.myGhost,
            partnerGhost: _locationViewModel.partnerGhost,
            distanceLine: _locationViewModel.distanceLine,
            onChooseGhost: _locationViewModel.chooseGhost,
            ghostBusy: _locationViewModel.ghostBusy,
            errorText: _locationViewModel.errorText,
            onClose: onClose,
          );
        },
      ),
      onOpenDoodle: _openDoodleCanvas,
      onLogOut: () => AppScope.of(context, listen: false).logOut(),
      extras: [
        if (KehaiForegroundTask.isSupported)
          PixelButton(
            label: AppStrings.superpowersOpen,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PhoneSuperpowersScreen(),
              ),
            ),
          ),
      ],
    );
  }

  /// The little always-there card. Same view models, same live data — only
  /// the amount of it on screen changes.
  Widget _buildMini() => MiniWindowHost(
    partnerName: _viewModel.partner?.name ?? '',
    status: _viewModel.partnerStatus,
    phoneOnline: _viewModel.partnerPhoneOnline,
    desktopOnline: _viewModel.partnerDesktopOnline,
    ambientLine: _viewModel.partnerAmbientLine,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final windowMode = DesktopWindowService.instance.windowMode;

    return ListenableBuilder(
      listenable: windowMode,
      builder: (context, _) {
        final mini = DesktopWindowService.isSupported && windowMode.isMini;
        return Scaffold(
          // The card paints its own frame edge to edge; a Scaffold colour
          // under it would fill the pixel corners back in.
          backgroundColor: mini ? Colors.transparent : colors.bg,
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) {
                if (_viewModel.isLoading) {
                  return Center(
                    child: Text(
                      AppStrings.loading,
                      style: AppTextStyles.body1.copyWith(color: colors.ink),
                    ),
                  );
                }
                if (mini) return _buildMini();
                return ListenableBuilder(
                  listenable: _doodleViewModel,
                  // The location view model feeds the partner card's
                  // distance line as well as its own section, so the card
                  // has to rebuild when a new point lands.
                  builder: (context, _) => ListenableBuilder(
                    listenable: _locationViewModel,
                    builder: (context, _) => HomeBody(
                      sections: _buildSections(context),
                      desktop: DesktopWindowService.isSupported,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
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
          Text(
            AppStrings.waitingBody,
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
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
                  style: AppTextStyles.heading.copyWith(
                    fontSize: 24,
                    letterSpacing: 4,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PixelButton(
                  label: AppStrings.copyCode,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: inviteCode!)),
                ),
                const SizedBox(width: 10),
                PixelButton(
                  primary: true,
                  label: AppStrings.retry,
                  onPressed: onRefresh,
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            PixelButton(
              primary: true,
              label: AppStrings.retry,
              onPressed: onRefresh,
            ),
          ],
        ],
      ),
    );
  }
}
