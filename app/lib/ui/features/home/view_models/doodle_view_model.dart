import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/doodle_repository.dart';
import '../../../../domain/models/doodle.dart';

/// Drives the doodle-to-partner feature: my latest doodle + the partner's,
/// kept fresh via realtime create/delete events on `doodles` — same
/// reconcile-by-action pattern as [CountdownsViewModel]/[NotesViewModel].
///
/// The partner's user id isn't known at construction time (it's discovered
/// asynchronously by [HomeViewModel]), so it's pushed in later via
/// [updatePartner] rather than taken as a constructor arg.
class DoodleViewModel extends ChangeNotifier {
  DoodleViewModel({
    required AuthRepository authRepository,
    required DoodleRepository doodleRepository,
  }) : _authRepository = authRepository,
       _doodleRepository = doodleRepository;

  final AuthRepository _authRepository;
  final DoodleRepository _doodleRepository;

  bool isLoading = true;
  Doodle? myDoodle;
  Doodle? partnerDoodle;

  String? _partnerId;
  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;
  String get _myId => _authRepository.currentUserId;

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        myDoodle = await _doodleRepository.latestByAuthor(coupleId, _myId);
      } catch (_) {
        // Leave it null — the "you sent" thumbnail just won't show.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _doodleRepository.subscribe((action, doodle) {
      if (doodle.coupleId != _coupleId) return;
      if (action == 'delete') {
        if (myDoodle?.id == doodle.id) myDoodle = null;
        if (partnerDoodle?.id == doodle.id) partnerDoodle = null;
      } else {
        _apply(doodle);
      }
      notifyListeners();
    });
  }

  void _apply(Doodle doodle) {
    if (doodle.authorId == _myId) {
      if (myDoodle == null || !doodle.created.isBefore(myDoodle!.created))
        myDoodle = doodle;
    } else if (doodle.authorId == _partnerId) {
      if (partnerDoodle == null ||
          !doodle.created.isBefore(partnerDoodle!.created))
        partnerDoodle = doodle;
    }
  }

  /// Called by the home screen once [HomeViewModel] resolves (or loses)
  /// the partner, so this view model knows whose doodles to fetch/show.
  Future<void> updatePartner(String? partnerId) async {
    if (partnerId == _partnerId) return;
    _partnerId = partnerId;
    if (partnerId == null) {
      partnerDoodle = null;
      notifyListeners();
      return;
    }
    final coupleId = _coupleId;
    if (coupleId == null) return;
    try {
      partnerDoodle = await _doodleRepository.latestByAuthor(
        coupleId,
        partnerId,
      );
      notifyListeners();
    } catch (_) {
      // Leave it null — the partner-card doodle just won't show.
    }
  }

  Future<void> send(Uint8List pngBytes) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _doodleRepository.create(
      coupleId: coupleId,
      authorId: _myId,
      pngBytes: pngBytes,
    );
  }

  Future<void> deleteMine() async {
    final id = myDoodle?.id;
    if (id == null) return;
    myDoodle = null;
    notifyListeners();
    await _doodleRepository.delete(id);
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
