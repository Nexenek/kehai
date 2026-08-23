import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/location_repository.dart';
import '../../../../domain/location_math.dart';
import '../../../../domain/models/couple_info.dart';
import '../../../../domain/models/ghost_state.dart';
import '../../../../domain/models/location_point.dart';
import '../../../core/strings/app_strings.dart';

/// Drives the "where we are" section and the partner card's distance
/// line: both latest points, both ghost states, and my own pause switch.
///
/// The partner's id and `ghost_until` arrive from [HomeViewModel] via
/// [updatePartner] rather than being fetched again here — same pattern as
/// [DoodleViewModel], one fewer request per open.
class LocationViewModel extends ChangeNotifier {
  LocationViewModel({
    required AuthRepository authRepository,
    required LocationRepository locationRepository,
  }) : _authRepository = authRepository,
       _locationRepository = locationRepository;

  final AuthRepository _authRepository;
  final LocationRepository _locationRepository;

  bool isLoading = true;
  bool ghostBusy = false;
  String? errorText;

  LocationPoint? myPoint;
  LocationPoint? partnerPoint;

  DateTime? myGhostUntil;
  DateTime? partnerGhostUntil;

  String partnerName = '';
  String? _partnerId;

  UnsubscribeFunc? _pointsUnsub;
  UnsubscribeFunc? _ghostUnsub;
  Timer? _tickTimer;

  String get _myId => _authRepository.currentUserId;

  GhostState get myGhost => resolveGhostState(myGhostUntil);
  GhostState get partnerGhost => resolveGhostState(partnerGhostUntil);

  /// "~4.2 km apart ♡", or null when the contract says to hide it — stale
  /// points, a missing point, or a paused partner with nothing fresh.
  String? get distanceLine => formatDistanceApart(
    mine: myPoint,
    theirs: partnerPoint,
    partnerGhost: partnerGhost,
    myGhost: myGhost,
  );

  Future<void> init() async {
    // "as of Xm ago", the 24h staleness cutoff and a ghost timer running
    // out are all clock-relative, so re-render on a slow tick — same 20s
    // cadence HomeViewModel uses.
    _tickTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => notifyListeners(),
    );

    myGhostUntil = await _guard(() => _locationRepository.readGhostUntil(_myId));
    myPoint = await _guard(() => _locationRepository.latestForUser(_myId));

    isLoading = false;
    notifyListeners();

    _pointsUnsub = await _locationRepository.subscribe(_applyPoint);
    _ghostUnsub = await _locationRepository.subscribeGhost((userId, until) {
      if (userId == _myId) {
        myGhostUntil = until;
      } else if (userId == _partnerId) {
        partnerGhostUntil = until;
      } else {
        return;
      }
      notifyListeners();
    });
  }

  void _applyPoint(LocationPoint point) {
    if (point.userId == _myId) {
      if (_isNewer(point, myPoint)) myPoint = point;
    } else if (point.userId == _partnerId) {
      if (_isNewer(point, partnerPoint)) partnerPoint = point;
    } else {
      return;
    }
    notifyListeners();
  }

  static bool _isNewer(LocationPoint incoming, LocationPoint? current) =>
      current == null || !incoming.recorded.isBefore(current.recorded);

  /// Called by the home screen when [HomeViewModel] resolves (or loses) the
  /// partner. Their `ghost_until` rides along on the same record, so their
  /// pause shows up without a second request.
  Future<void> updatePartner(Partner? partner) async {
    partnerName = partner?.name ?? '';
    partnerGhostUntil = partner?.ghostUntil;
    if (partner?.id == _partnerId) {
      notifyListeners();
      return;
    }
    _partnerId = partner?.id;
    if (_partnerId == null) {
      partnerPoint = null;
      notifyListeners();
      return;
    }
    partnerPoint = await _guard(
      () => _locationRepository.latestForUser(_partnerId!),
    );
    notifyListeners();
  }

  /// `null` turns sharing back on; the rest are the quick pauses.
  Future<void> chooseGhost(GhostOption? option) async {
    ghostBusy = true;
    errorText = null;
    notifyListeners();
    try {
      myGhostUntil = await _locationRepository.setGhost(option);
    } catch (_) {
      errorText = AppStrings.ghostFailed;
    } finally {
      ghostBusy = false;
      notifyListeners();
    }
  }

  /// Reads that are allowed to come back empty: while the server half of
  /// phase 3 is still landing there is no `locations` collection and no
  /// `ghost_until` field, and "no location yet ( . .)" is the honest thing
  /// to show rather than an error.
  Future<T?> _guard<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _pointsUnsub?.call();
    _ghostUnsub?.call();
    super.dispose();
  }
}
