import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/note_repository.dart';
import '../../../../domain/models/note.dart';
import '../../../../domain/models/note_color.dart';

/// Drives the "notes" RetroWindow: the couple's shared sticky notes,
/// realtime-subscribed the same way [HomeViewModel] subscribes to
/// statuses/devices.
class NotesViewModel extends ChangeNotifier {
  NotesViewModel({
    required AuthRepository authRepository,
    required NoteRepository noteRepository,
  })  : _authRepository = authRepository,
        _noteRepository = noteRepository;

  final AuthRepository _authRepository;
  final NoteRepository _noteRepository;

  bool isLoading = true;
  List<Note> notes = const [];

  UnsubscribeFunc? _notesUnsub;

  String? get _coupleId => _authRepository.coupleId;

  /// Pinned notes first; otherwise the order they were fetched/received in.
  List<Note> get sorted {
    final list = [...notes];
    list.sort((a, b) {
      if (a.pinned == b.pinned) return 0;
      return a.pinned ? -1 : 1;
    });
    return list;
  }

  Future<void> init() async {
    final coupleId = _coupleId;
    if (coupleId != null) {
      try {
        notes = await _noteRepository.fetchAll(coupleId);
      } catch (_) {
        // Leave the list empty — the window still renders its empty state.
      }
    }
    isLoading = false;
    notifyListeners();

    _notesUnsub = await _noteRepository.subscribe((action, note) {
      if (note.coupleId != _coupleId) return;
      if (action == 'delete') {
        notes = notes.where((n) => n.id != note.id).toList();
      } else {
        notes = [...notes.where((n) => n.id != note.id), note];
      }
      notifyListeners();
    });
  }

  Future<void> addNote({
    required String title,
    required String body,
    required NoteColor color,
    bool pinned = false,
  }) {
    final coupleId = _coupleId;
    if (coupleId == null) return Future.value();
    return _noteRepository.create(coupleId: coupleId, title: title, body: body, color: color, pinned: pinned);
  }

  Future<void> updateNote(
    String id, {
    required String title,
    required String body,
    required NoteColor color,
    bool pinned = false,
  }) {
    return _noteRepository.update(id, title: title, body: body, color: color, pinned: pinned);
  }

  Future<void> deleteNote(String id) => _noteRepository.delete(id);

  @override
  void dispose() {
    _notesUnsub?.call();
    super.dispose();
  }
}
