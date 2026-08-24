import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/mood_jar_repository.dart';
import 'package:couples_app/domain/models/mood_entry.dart';
import 'package:couples_app/domain/mood_jar_grouping.dart';
import 'package:couples_app/ui/features/jar/mood_jar_view_model.dart';

/// A logged-in, paired user without a server — same shape as
/// `pet_view_model_test.dart`'s `_FakeAuth`.
class _FakeAuth extends AuthRepository {
  _FakeAuth({this.couple = 'couple1'}) : super(PocketBase('https://x.invalid'));

  final String? couple;

  @override
  String? get coupleId => couple;

  @override
  String get currentUserId => 'me';
}

/// In-memory stand-in for `mood_entries`: hands back whatever the test
/// wired up for `fetchRecent`, and exposes [emit] to push a realtime bead
/// straight into whatever callback `init()` registered.
class _FakeMoodJar extends MoodJarRepository {
  _FakeMoodJar({this.initial = const []})
    : super(PocketBase('https://x.invalid'));

  List<MoodEntry> initial;
  bool failFetch = false;
  void Function(MoodEntry entry)? _listener;

  @override
  Future<List<MoodEntry>> fetchRecent(
    String coupleId, {
    int limit = 200,
  }) async {
    if (failFetch) throw ClientException(statusCode: 500);
    return initial;
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    void Function(MoodEntry entry) onEntry,
  ) async {
    _listener = onEntry;
    return () async => _listener = null;
  }

  void emit(MoodEntry entry) => _listener?.call(entry);
}

MoodEntry _entry(
  String id, {
  String userId = 'partner',
  String mood = 'happy',
  String note = '',
  DateTime? created,
}) => MoodEntry(
  id: id,
  coupleId: 'couple1',
  userId: userId,
  mood: mood,
  note: note,
  created: created ?? DateTime(2026, 8, 24, 10),
);

void main() {
  test('with no partner yet, init leaves the jar empty rather than '
      'fetching', () async {
    final repository = _FakeMoodJar(initial: [_entry('e1')]);
    final viewModel = MoodJarViewModel(
      authRepository: _FakeAuth(couple: null),
      moodJarRepository: repository,
    );

    await viewModel.init();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.entries, isEmpty);
  });

  test('init loads the recent entries and stops loading', () async {
    final entries = [_entry('e1'), _entry('e2')];
    final repository = _FakeMoodJar(initial: entries);
    final viewModel = MoodJarViewModel(
      authRepository: _FakeAuth(),
      moodJarRepository: repository,
    );

    await viewModel.init();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.entries, entries);
  });

  test(
    'a fetch failure still stops loading and leaves the jar empty',
    () async {
      final repository = _FakeMoodJar()..failFetch = true;
      final viewModel = MoodJarViewModel(
        authRepository: _FakeAuth(),
        moodJarRepository: repository,
      );

      await viewModel.init();

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.entries, isEmpty);
    },
  );

  test('a realtime bead is prepended, newest first', () async {
    final repository = _FakeMoodJar(initial: [_entry('old')]);
    final viewModel = MoodJarViewModel(
      authRepository: _FakeAuth(),
      moodJarRepository: repository,
    );
    await viewModel.init();

    var notified = 0;
    viewModel.addListener(() => notified++);
    repository.emit(_entry('new'));

    expect(viewModel.entries.map((e) => e.id), ['new', 'old']);
    expect(notified, 1);
  });

  test('a realtime bead for a different couple is ignored (a stale '
      'subscription from before a repair, e.g.)', () async {
    final repository = _FakeMoodJar(initial: const []);
    final viewModel = MoodJarViewModel(
      authRepository: _FakeAuth(),
      moodJarRepository: repository,
    );
    await viewModel.init();

    repository.emit(
      MoodEntry(
        id: 'foreign',
        coupleId: 'someone-elses-couple',
        userId: 'x',
        mood: 'happy',
        note: '',
        created: DateTime(2026, 8, 24),
      ),
    );

    expect(viewModel.entries, isEmpty);
  });

  test('a duplicate id (e.g. an echo) is not added twice', () async {
    final repository = _FakeMoodJar(initial: [_entry('e1')]);
    final viewModel = MoodJarViewModel(
      authRepository: _FakeAuth(),
      moodJarRepository: repository,
    );
    await viewModel.init();

    repository.emit(_entry('e1'));

    expect(viewModel.entries, hasLength(1));
  });

  group('dayGroups', () {
    test('buckets by clock.now(), not DateTime.now()', () {
      fakeAsync((async) {
        withClock(Clock.fixed(DateTime(2026, 8, 24, 12)), () {
          final repository = _FakeMoodJar(
            initial: [
              _entry('today', created: DateTime(2026, 8, 24, 9)),
              _entry('yesterday', created: DateTime(2026, 8, 23, 20)),
            ],
          );
          final viewModel = MoodJarViewModel(
            authRepository: _FakeAuth(),
            moodJarRepository: repository,
          );
          viewModel.init();
          async.flushMicrotasks();

          final groups = viewModel.dayGroups;
          expect(groups, hasLength(2));
          expect(groups[0].kind, JarDayKind.today);
          expect(groups[1].kind, JarDayKind.yesterday);
        });
      });
    });

    test('reads live off the clock — a jar left open across midnight '
        're-labels on the next read', () {
      fakeAsync((async) {
        withClock(Clock.fixed(DateTime(2026, 8, 24, 23, 50)), () {
          final repository = _FakeMoodJar(
            initial: [_entry('e', created: DateTime(2026, 8, 24, 9))],
          );
          final viewModel = MoodJarViewModel(
            authRepository: _FakeAuth(),
            moodJarRepository: repository,
          );
          viewModel.init();
          async.flushMicrotasks();

          expect(viewModel.dayGroups.single.kind, JarDayKind.today);
        });

        // A fresh fixed clock past midnight — same entries, later "now".
        withClock(Clock.fixed(DateTime(2026, 8, 25, 0, 10)), () {
          final repository = _FakeMoodJar(
            initial: [_entry('e', created: DateTime(2026, 8, 24, 9))],
          );
          final viewModel = MoodJarViewModel(
            authRepository: _FakeAuth(),
            moodJarRepository: repository,
          );
          viewModel.init();
          async.flushMicrotasks();

          expect(viewModel.dayGroups.single.kind, JarDayKind.yesterday);
        });
      });
    });
  });
}
