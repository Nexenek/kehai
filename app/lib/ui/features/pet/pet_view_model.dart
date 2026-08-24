import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/pet_repository.dart';
import '../../../domain/models/pet.dart';
import '../../../domain/models/pet_event.dart';
import '../../core/strings/app_strings.dart';
import 'pet_state.dart';

/// Drives the shared pet window: adopt-or-load on init, four care actions,
/// and live updates so your partner's feed shows up on your screen without
/// a refresh.
///
/// Care actions are optimistic — the sprite reacts the instant you tap, and
/// the server write reconciles behind it. A failed write rolls the pet back
/// and says so plainly rather than pretending it worked.
class PetViewModel extends ChangeNotifier {
  PetViewModel({
    required AuthRepository authRepository,
    required PetRepository petRepository,
    DateTime Function()? clock,
  }) : _authRepository = authRepository,
       _petRepository = petRepository,
       _clock = clock ?? DateTime.now;

  final AuthRepository _authRepository;
  final PetRepository _petRepository;

  /// Injectable "now" — the derived state is a pure function of the pet's
  /// timestamps and this clock, so tests can stand at any hour they like.
  final DateTime Function() _clock;

  bool isLoading = true;
  Pet? pet;

  /// Set when a care action couldn't reach the server; cleared as soon as
  /// the next one is attempted.
  String? error;

  UnsubscribeFunc? _unsub;

  /// The care-log "story" — empty until [loadHistory] is called (the story
  /// dialog opens it), so a window that never opens the story never pays
  /// for the fetch.
  List<PetEvent> history = const [];

  /// True while [loadHistory]'s fetch is in flight.
  bool historyLoading = false;

  /// True once [history] holds a successful fetch, so re-opening the story
  /// doesn't refetch every time. Left false after a failed fetch, so the
  /// next open retries instead of getting stuck empty forever.
  bool historyLoaded = false;

  String? get _coupleId => _authRepository.coupleId;

  /// The pet's mood right now. Recomputed on every read (it's pure and
  /// cheap), so it stays honest as the hours pass without any timer.
  PetState get state =>
      derivePetState(fedAt: pet?.fedAt, petAt: pet?.petAt, now: _clock());

  /// Injectable "now", exposed for the story dialog's relative-time labels
  /// so they share the same clock as [state] rather than reaching for
  /// `DateTime.now()` directly.
  DateTime get clockNow => _clock();

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        pet = await _petRepository.getOrCreate(coupleId, now: _clock());
      } catch (_) {
        // Leave pet null — the window shows its gentle "not here right
        // now" state instead of an exception.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _petRepository.subscribe((updated) {
      if (updated.coupleId != _coupleId) return;
      pet = updated;
      notifyListeners();
    });
  }

  /// Loads the care-log "story" the first time it's asked for, and is a
  /// no-op after that (or while a fetch is already in flight) — the story
  /// dialog calls this on open, so opening it twice doesn't double-fetch.
  Future<void> loadHistory() async {
    if (historyLoaded || historyLoading) return;
    final coupleId = _coupleId;
    if (coupleId == null) return;

    historyLoading = true;
    notifyListeners();

    try {
      history = await _petRepository.fetchEvents(coupleId);
      historyLoaded = true;
    } catch (_) {
      // Leave history as-is (likely still empty) — see [historyLoaded]'s
      // doc comment for why this stays false on failure.
    }

    historyLoading = false;
    notifyListeners();
  }

  Future<void> feed() => _act(
    (current) => _petRepository.feed(
      current,
      userId: _authRepository.currentUserId,
      now: _clock(),
    ),
    optimistic: (current) => current.copyWith(fedAt: _clock()),
  );

  Future<void> cuddle() => _act(
    (current) => _petRepository.cuddle(
      current,
      userId: _authRepository.currentUserId,
      now: _clock(),
    ),
    optimistic: (current) => current.copyWith(petAt: _clock()),
  );

  Future<void> dress({required PetVariant variant, required PetOutfit outfit}) {
    return _act(
      (current) => _petRepository.dress(
        current,
        userId: _authRepository.currentUserId,
        variant: variant,
        outfit: outfit,
      ),
      optimistic: (current) =>
          current.copyWith(variant: variant, outfit: outfit),
    );
  }

  Future<void> rename(String name) => _act(
    (current) => _petRepository.rename(
      current,
      userId: _authRepository.currentUserId,
      name: name,
    ),
    optimistic: (current) => current.copyWith(name: name.trim()),
  );

  Future<void> _act(
    Future<Pet> Function(Pet current) write, {
    required Pet Function(Pet current) optimistic,
  }) async {
    final current = pet;
    if (current == null) return;

    error = null;
    pet = optimistic(current);
    notifyListeners();

    try {
      final saved = await write(current);
      // Realtime may have delivered a newer version already; only take the
      // response if it's still the same record.
      if (pet?.id == saved.id) pet = saved;
    } catch (_) {
      pet = current;
      error = AppStrings.petActionFailed;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
