import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/couple_repository.dart';
import '../../../../data/repositories/device_repository.dart';
import '../../../../data/repositories/status_repository.dart';
import '../../../../data/services/device_info_service.dart';
import '../../../../data/services/heartbeat_service.dart';
import '../../../../data/services/prefs_service.dart';
import '../../../../domain/models/ambient_line.dart';
import '../../../../domain/models/couple_info.dart';
import '../../../../domain/models/device_status.dart';
import '../../../../domain/models/partner_status.dart';

/// Drives "our desktop" — the home screen. Owns the partner's live status
/// + device glyphs (via realtime subscriptions) and the caller's own mood
/// picker state, and keeps the heartbeat ticking while the screen is
/// alive.
class HomeViewModel extends ChangeNotifier with WidgetsBindingObserver {
  HomeViewModel({
    required AuthRepository authRepository,
    required CoupleRepository coupleRepository,
    required StatusRepository statusRepository,
    required DeviceRepository deviceRepository,
    required HeartbeatService heartbeatService,
    required DeviceInfoService deviceInfoService,
    required PrefsService prefs,
  })  : _authRepository = authRepository,
        _coupleRepository = coupleRepository,
        _statusRepository = statusRepository,
        _deviceRepository = deviceRepository,
        _heartbeatService = heartbeatService,
        _deviceInfoService = deviceInfoService,
        _prefs = prefs;

  final AuthRepository _authRepository;
  final CoupleRepository _coupleRepository;
  final StatusRepository _statusRepository;
  final DeviceRepository _deviceRepository;
  final HeartbeatService _heartbeatService;
  final DeviceInfoService _deviceInfoService;
  final PrefsService _prefs;

  bool isLoading = true;
  Partner? partner;
  PartnerStatus? partnerStatus;
  List<DeviceStatus> partnerDevices = const [];

  String myMoodId = 'happy';
  String myNote = '';
  bool isSavingMood = false;

  UnsubscribeFunc? _statusUnsub;
  UnsubscribeFunc? _deviceUnsub;
  Timer? _tickTimer;

  String get myName => _authRepository.currentUser?.get<String>('name') ?? '';
  String? get inviteCode => _prefs.inviteCode;

  bool get hasPartner => partner != null;

  bool get partnerPhoneOnline =>
      partnerDevices.any((d) => d.kind == 'phone' && d.isOnline);
  bool get partnerDesktopOnline =>
      partnerDevices.any((d) => d.kind == 'desktop' && d.isOnline);

  /// Precedence-resolved partner-card ambient line — see
  /// [resolveAmbientLine] (kb/platform-desktop.md "Telemetry contract").
  AmbientLine? get partnerAmbientLine => resolveAmbientLine(partnerDevices);

  /// Partner's phone low-battery/charging glyph — see [resolvePhoneBattery].
  BatteryGlyphInfo get partnerBatteryInfo => resolvePhoneBattery(partnerDevices);

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    _heartbeatService.start();

    // Re-render every 20s so "updated Xm ago" stays fresh without a manual
    // pull-to-refresh.
    _tickTimer = Timer.periodic(const Duration(seconds: 20), (_) => notifyListeners());

    final myStatus = await _statusRepository.fetchStatus(_authRepository.currentUserId);
    if (myStatus != null) {
      myMoodId = myStatus.moodId.isEmpty ? myMoodId : myStatus.moodId;
      myNote = myStatus.note;
    }

    await _refreshPartner();

    _statusUnsub = await _statusRepository.subscribe((status) {
      if (partner != null && status.userId == partner!.id) {
        partnerStatus = status;
        notifyListeners();
      } else if (status.userId == _authRepository.currentUserId) {
        // Reflect edits made from another of my own devices.
        myMoodId = status.moodId.isEmpty ? myMoodId : status.moodId;
        myNote = status.note;
        notifyListeners();
      }
    });

    _deviceUnsub = await _deviceRepository.subscribe((device) {
      if (partner != null && device.ownerId == partner!.id) {
        partnerDevices = [
          ...partnerDevices.where((d) => d.id != device.id),
          device,
        ];
        notifyListeners();
      }
    });

    isLoading = false;
    notifyListeners();
  }

  Future<void> _refreshPartner() async {
    partner = await _coupleRepository.fetchPartner();
    if (partner != null) {
      partnerStatus = await _statusRepository.fetchStatus(partner!.id);
      partnerDevices = await _deviceRepository.fetchDevicesForOwner(partner!.id);
    }
  }

  /// Manual pull for the waiting-for-partner state, so the user can check
  /// again without restarting the app.
  Future<void> checkForPartner() async {
    await _refreshPartner();
    notifyListeners();
  }

  Future<void> pickMood(String moodId) async {
    myMoodId = moodId;
    notifyListeners();
    await _saveStatus();
  }

  Future<void> updateNote(String note) async {
    myNote = note;
    await _saveStatus();
  }

  Future<void> _saveStatus() async {
    isSavingMood = true;
    notifyListeners();
    try {
      await _statusRepository.upsertMyStatus(
        userId: _authRepository.currentUserId,
        moodId: myMoodId,
        note: myNote,
        sourceKind: _deviceInfoService.kind,
      );
    } catch (_) {
      // Silent — realtime echo will reconcile, and the picker already
      // reflects the intended local state.
    } finally {
      isSavingMood = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _heartbeatService.pingNow();
      checkForPartner();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _statusUnsub?.call();
    _deviceUnsub?.call();
    _heartbeatService.stop();
    super.dispose();
  }
}
