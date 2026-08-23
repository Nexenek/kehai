import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/art_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/couple_repository.dart';
import '../../../../data/repositories/device_repository.dart';
import '../../../../data/repositories/status_repository.dart';
import '../../../../data/services/background/partner_widget.dart';
import '../../../../data/services/device_info_service.dart';
import '../../../../data/services/heartbeat_service.dart';
import '../../../../data/services/prefs_service.dart';
import '../../../../domain/art_scene.dart';
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
    ArtRepository? artRepository,
    Future<bool> Function()? handOffPresenceToBackground,
  }) : _artRepository = artRepository,
       _handOffPresenceToBackground = handOffPresenceToBackground,
       _authRepository = authRepository,
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

  /// The couple's paper-doll art (ADR-13). Optional so every existing
  /// caller (and every existing test) keeps compiling unchanged: null
  /// simply means no art is loaded and both portraits stay on the kaomoji.
  final ArtRepository? _artRepository;

  /// Android's "start the foreground service" hook (see
  /// [AppController.handOffPresenceToBackground]). Null on desktop and in
  /// tests, which is the same as "nobody else is heartbeating".
  final Future<bool> Function()? _handOffPresenceToBackground;

  /// False once presence has been handed to the background isolate — this
  /// view model then stops touching the heartbeat entirely, so the device
  /// row has exactly one writer.
  bool _ownsHeartbeat = true;

  bool isLoading = true;
  Partner? partner;
  PartnerStatus? partnerStatus;
  List<DeviceStatus> partnerDevices = const [];

  /// Every art layer the couple has drawn, unfiltered — the compositor
  /// picks from these on every rebuild rather than us caching a resolved
  /// scene, so a mood change reaches the portrait in the same frame the
  /// status does.
  List<ArtLayer> artLayers = const [];

  String myMoodId = 'happy';
  String myNote = '';
  bool isSavingMood = false;

  UnsubscribeFunc? _statusUnsub;
  UnsubscribeFunc? _deviceUnsub;
  UnsubscribeFunc? _artUnsub;
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
  BatteryGlyphInfo get partnerBatteryInfo =>
      resolvePhoneBattery(partnerDevices);

  /// The partner's composited status scene (ADR-13), resolved fresh from
  /// their current mood + ambient state. Empty means "no art fits right
  /// now" — the portraits then show the mood kaomoji, which is always a
  /// complete answer rather than a placeholder.
  List<ArtLayer> get partnerArtScene => resolveArtScene(
    artLayers,
    moodId: partnerStatus?.moodId,
    ambientKind: artAmbientKindFor(partnerAmbientLine),
  );

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    final handedOff = await _handOffPresenceToBackground?.call() ?? false;
    _ownsHeartbeat = !handedOff;
    if (_ownsHeartbeat) _heartbeatService.start();

    // Re-render every 20s so "updated Xm ago" stays fresh without a manual
    // pull-to-refresh.
    _tickTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => notifyListeners(),
    );

    final myStatus = await _statusRepository.fetchStatus(
      _authRepository.currentUserId,
    );
    if (myStatus != null) {
      myMoodId = myStatus.moodId.isEmpty ? myMoodId : myStatus.moodId;
      myNote = myStatus.note;
    }

    await _refreshPartner();

    _statusUnsub = await _statusRepository.subscribe((status) {
      if (partner != null && status.userId == partner!.id) {
        partnerStatus = status;
        notifyListeners();
        unawaited(_syncWidget());
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
        unawaited(_syncWidget());
      }
    });

    await _initArt();

    isLoading = false;
    notifyListeners();
  }

  /// Loads the couple's art and stays subscribed, so a layer uploaded on
  /// the artist's machine appears in the other partner's window without a
  /// restart — the "draw it and watch it land" moment the feature exists
  /// for. Every failure here is silent by design: no art simply means the
  /// kaomoji portrait, which is a perfectly good partner window.
  Future<void> _initArt() async {
    final art = _artRepository;
    if (art == null) return;
    final coupleId = _authRepository.coupleId;
    if (coupleId != null) {
      try {
        artLayers = await art.fetchAll(coupleId);
      } catch (_) {
        // Server without migration 10 yet, or offline — keep the kaomoji.
      }
    }
    _artUnsub = await art.subscribe((action, layer) {
      if (layer.coupleId != _authRepository.coupleId) return;
      artLayers = action == 'delete'
          ? artLayers.where((l) => l.id != layer.id).toList()
          : [...artLayers.where((l) => l.id != layer.id), layer];
      notifyListeners();
    });
  }

  Future<void> _refreshPartner() async {
    partner = await _coupleRepository.fetchPartner();
    if (partner != null) {
      partnerStatus = await _statusRepository.fetchStatus(partner!.id);
      partnerDevices = await _deviceRepository.fetchDevicesForOwner(
        partner!.id,
      );
    }
    unawaited(_syncWidget());
  }

  /// Keeps the home-screen widget's SharedPreferences in sync with the
  /// partner's name/status/devices — the UI-isolate counterpart to
  /// KehaiTaskHandler's own call, so the widget stays fresh even when the
  /// background service isn't running but the app is.
  Future<void> _syncWidget() => updatePartnerWidget(
    partnerName: partner?.name,
    status: partnerStatus,
    partnerDevices: partnerDevices,
  );

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
      if (_ownsHeartbeat) _heartbeatService.pingNow();
      checkForPartner();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _statusUnsub?.call();
    _deviceUnsub?.call();
    _artUnsub?.call();
    // Deliberately not stopping the foreground service here: surviving
    // this screen going away is the whole point of it.
    if (_ownsHeartbeat) _heartbeatService.stop();
    super.dispose();
  }
}
