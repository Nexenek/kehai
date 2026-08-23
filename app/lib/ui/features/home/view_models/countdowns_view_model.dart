import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/countdown_repository.dart';
import '../../../../data/repositories/couple_repository.dart';
import '../../../../domain/day_math.dart';
import '../../../../domain/models/countdown.dart';

/// Drives the "countdowns" RetroWindow: the couple's shared countdowns plus
/// the anniversary "together N days" chip. Realtime-subscribed the same way
/// [HomeViewModel] subscribes to statuses/devices.
class CountdownsViewModel extends ChangeNotifier {
  CountdownsViewModel({
    required AuthRepository authRepository,
    required CoupleRepository coupleRepository,
    required CountdownRepository countdownRepository,
  }) : _authRepository = authRepository,
       _coupleRepository = coupleRepository,
       _countdownRepository = countdownRepository;

  final AuthRepository _authRepository;
  final CoupleRepository _coupleRepository;
  final CountdownRepository _countdownRepository;

  bool isLoading = true;
  List<Countdown> countdowns = const [];
  DateTime? anniversary;

  UnsubscribeFunc? _countdownUnsub;
  UnsubscribeFunc? _anniversaryUnsub;

  String? get _coupleId => _authRepository.coupleId;

  /// Nearest-future-first; already-passed countdowns sink to the end
  /// (still shown, per spec, as "N days ago").
  List<Countdown> get sorted {
    final list = [...countdowns]..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// The soonest countdown that hasn't happened yet (today counts as
  /// upcoming) — highlighted with the accent color in the row list.
  Countdown? get nearestUpcoming {
    final now = DateTime.now();
    for (final c in sorted) {
      if (daysUntil(c.date, now: now) >= 0) return c;
    }
    return null;
  }

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        countdowns = await _countdownRepository.fetchAll(coupleId);
        anniversary = await _coupleRepository.fetchAnniversary();
      } catch (_) {
        // Leave lists empty — the window still renders its empty state.
      }
    }
    isLoading = false;
    notifyListeners();

    _countdownUnsub = await _countdownRepository.subscribe((action, countdown) {
      if (countdown.coupleId != _coupleId) return;
      if (action == 'delete') {
        countdowns = countdowns.where((c) => c.id != countdown.id).toList();
      } else {
        countdowns = [
          ...countdowns.where((c) => c.id != countdown.id),
          countdown,
        ];
      }
      notifyListeners();
    });

    _anniversaryUnsub = await _coupleRepository.subscribeAnniversary((date) {
      anniversary = date;
      notifyListeners();
    });
  }

  Future<void> addCountdown({
    required String title,
    required DateTime date,
    String kaomoji = '',
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _countdownRepository.create(
      coupleId: coupleId,
      title: title,
      date: date,
      kaomoji: kaomoji,
    );
  }

  Future<void> updateCountdown(
    String id, {
    required String title,
    required DateTime date,
    String kaomoji = '',
  }) {
    return _countdownRepository.update(
      id,
      title: title,
      date: date,
      kaomoji: kaomoji,
    );
  }

  Future<void> deleteCountdown(String id) => _countdownRepository.delete(id);

  Future<void> setAnniversary(DateTime date) async {
    anniversary = date;
    notifyListeners();
    await _coupleRepository.updateAnniversary(date);
  }

  @override
  void dispose() {
    _countdownUnsub?.call();
    _anniversaryUnsub?.call();
    super.dispose();
  }
}
