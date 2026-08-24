import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/mood_jar_repository.dart';
import '../../../domain/models/mood_entry.dart';
import '../../../domain/mood_jar_grouping.dart';

/// Drives the mood jar window: loads the couple's recent beads and keeps
/// them fresh via realtime create events. Read-only, like the repository
/// underneath it — there is no add/edit/delete here, only "a bead just
/// landed".
class MoodJarViewModel extends ChangeNotifier {
  MoodJarViewModel({
    required AuthRepository authRepository,
    required MoodJarRepository moodJarRepository,
  }) : _authRepository = authRepository,
       _moodJarRepository = moodJarRepository;

  final AuthRepository _authRepository;
  final MoodJarRepository _moodJarRepository;

  bool isLoading = true;

  /// Newest first — exactly what [MoodJarRepository.fetchRecent] returns,
  /// kept that way through realtime prepends too.
  List<MoodEntry> entries = const [];

  UnsubscribeFunc? _unsub;

  String? get _coupleId => _authRepository.coupleId;
  String get myUserId => _authRepository.currentUserId;

  /// [entries] bucketed by local calendar day, newest day first. Computed
  /// fresh against `clock.now()` on every read, so a jar left open across
  /// midnight relabels "today" -> "yesterday" the next time it rebuilds.
  List<JarDayGroup> get dayGroups =>
      groupMoodEntriesByDay(entries, now: clock.now());

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        entries = await _moodJarRepository.fetchRecent(coupleId);
      } catch (_) {
        // Leave it empty — the window still renders its empty state.
      }
    }
    isLoading = false;
    notifyListeners();

    _unsub = await _moodJarRepository.subscribe((entry) {
      if (entry.coupleId != _coupleId) return;
      if (entries.any((e) => e.id == entry.id)) return;
      entries = [entry, ...entries];
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }
}
