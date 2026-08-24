import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/pet_repository.dart';
import 'package:couples_app/domain/models/pet.dart';
import 'package:couples_app/domain/models/pet_event.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/pet/pet_state.dart';
import 'package:couples_app/ui/features/pet/pet_view_model.dart';

final _now = DateTime(2026, 8, 23, 15);

/// A logged-in, paired user without a server: only the two getters the pet
/// view model reads are stubbed.
class _FakeAuth extends AuthRepository {
  _FakeAuth({this.couple = 'couple1'}) : super(PocketBase('https://x.invalid'));

  final String? couple;

  @override
  String? get coupleId => couple;

  @override
  String get currentUserId => 'userA';
}

/// In-memory stand-in for the `pets` collection: records the calls, hands
/// back whatever the test wired up, and can push a realtime update.
class _FakePets extends PetRepository {
  _FakePets({this.initial}) : super(PocketBase('https://x.invalid'));

  Pet? initial;
  final calls = <String>[];
  bool failNextWrite = false;
  void Function(Pet pet)? _listener;

  List<PetEvent> events = const [];
  bool failEvents = false;

  @override
  Future<List<PetEvent>> fetchEvents(String coupleId, {int limit = 100}) async {
    calls.add('fetchEvents');
    if (failEvents) throw ClientException(statusCode: 500);
    return events;
  }

  @override
  Future<Pet?> getOrCreate(String coupleId, {DateTime? now}) async {
    calls.add('getOrCreate');
    return initial;
  }

  Future<Pet> _write(Pet pet, String call) async {
    calls.add(call);
    if (failNextWrite) {
      failNextWrite = false;
      throw ClientException(statusCode: 500);
    }
    return pet;
  }

  @override
  Future<Pet> feed(Pet pet, {required String userId, DateTime? now}) =>
      _write(pet.copyWith(fedAt: now ?? _now), 'feed:$userId');

  @override
  Future<Pet> cuddle(Pet pet, {required String userId, DateTime? now}) =>
      _write(pet.copyWith(petAt: now ?? _now), 'pet:$userId');

  @override
  Future<Pet> dress(
    Pet pet, {
    required String userId,
    required PetVariant variant,
    required PetOutfit outfit,
  }) => _write(pet.copyWith(variant: variant, outfit: outfit), 'dress:$userId');

  @override
  Future<Pet> rename(Pet pet, {required String userId, required String name}) =>
      _write(pet.copyWith(name: name.trim()), 'rename:$userId');

  @override
  Future<UnsubscribeFunc> subscribe(void Function(Pet pet) onChange) async {
    _listener = onChange;
    return () async => _listener = null;
  }

  /// Simulates the partner's change arriving over the realtime channel.
  void pushFromPartner(Pet pet) => _listener?.call(pet);

  bool get isSubscribed => _listener != null;
}

Pet _pet({
  String name = '',
  PetVariant variant = PetVariant.blob,
  PetOutfit outfit = PetOutfit.none,
  Duration fedAgo = Duration.zero,
  Duration petAgo = Duration.zero,
  String coupleId = 'couple1',
}) => Pet(
  id: 'pet1',
  coupleId: coupleId,
  name: name,
  variant: variant,
  outfit: outfit,
  fedAt: _now.subtract(fedAgo),
  petAt: _now.subtract(petAgo),
);

PetViewModel _viewModel(_FakePets pets, {String? couple = 'couple1'}) =>
    PetViewModel(
      authRepository: _FakeAuth(couple: couple),
      petRepository: pets,
      clock: () => _now,
    );

void main() {
  test('init adopts-or-loads the pet and subscribes for the partner', () async {
    final pets = _FakePets(initial: _pet(name: 'mochi'));
    final viewModel = _viewModel(pets);

    await viewModel.init();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.pet?.name, 'mochi');
    expect(pets.calls, ['getOrCreate']);
    expect(pets.isSubscribed, isTrue);
  });

  test('an unpaired user gets no pet but still stops loading', () async {
    final pets = _FakePets(initial: _pet());
    final viewModel = _viewModel(pets, couple: null);

    await viewModel.init();

    expect(viewModel.pet, isNull);
    expect(viewModel.isLoading, isFalse);
    expect(pets.calls, isEmpty);
  });

  test('a server that cannot be reached leaves a gentle empty state', () async {
    final pets = _FakePets(initial: null);
    final viewModel = _viewModel(pets);

    await viewModel.init();

    expect(viewModel.pet, isNull);
    expect(viewModel.isLoading, isFalse);
  });

  test('feeding is optimistic, then reconciled with the server', () async {
    final pets = _FakePets(initial: _pet(fedAgo: const Duration(days: 2)));
    final viewModel = _viewModel(pets);
    await viewModel.init();

    expect(viewModel.state.hunger, PetHunger.hungry);

    final pending = viewModel.feed();
    // The sprite has already cheered up, before the write comes back.
    expect(viewModel.state.hunger, PetHunger.full);
    await pending;

    expect(viewModel.state.hunger, PetHunger.full);
    expect(pets.calls, ['getOrCreate', 'feed:userA']);
    expect(viewModel.error, isNull);
  });

  test('petting bumps only the cuddle clock', () async {
    final pets = _FakePets(
      initial: _pet(
        fedAgo: const Duration(days: 2),
        petAgo: const Duration(days: 2),
      ),
    );
    final viewModel = _viewModel(pets);
    await viewModel.init();

    await viewModel.cuddle();

    expect(viewModel.state.cuddles, PetCuddles.cozy);
    expect(viewModel.state.hunger, PetHunger.hungry, reason: 'still unfed');
    expect(pets.calls.last, 'pet:userA');
  });

  test('a failed write rolls back and says so honestly', () async {
    final pets = _FakePets(initial: _pet(fedAgo: const Duration(days: 2)))
      ..failNextWrite = true;
    final viewModel = _viewModel(pets);
    await viewModel.init();

    await viewModel.feed();

    expect(viewModel.state.hunger, PetHunger.hungry, reason: 'rolled back');
    expect(viewModel.error, AppStrings.petActionFailed);

    // The next attempt clears the message before trying again.
    await viewModel.feed();
    expect(viewModel.error, isNull);
    expect(viewModel.state.hunger, PetHunger.full);
  });

  test('dressing and renaming go through as one update each', () async {
    final pets = _FakePets(initial: _pet());
    final viewModel = _viewModel(pets);
    await viewModel.init();

    await viewModel.dress(variant: PetVariant.star, outfit: PetOutfit.crown);
    expect(viewModel.pet?.variant, PetVariant.star);
    expect(viewModel.pet?.outfit, PetOutfit.crown);

    await viewModel.rename('  mochi  ');
    expect(viewModel.pet?.name, 'mochi');
    expect(pets.calls, ['getOrCreate', 'dress:userA', 'rename:userA']);
  });

  test('an empty rename falls back to kehai-chan without erroring', () async {
    final pets = _FakePets(initial: _pet(name: 'mochi'));
    final viewModel = _viewModel(pets);
    await viewModel.init();

    await viewModel.rename('   ');

    expect(viewModel.pet?.name, '');
    expect(viewModel.pet?.displayName, AppStrings.petDefaultName);
  });

  test("the partner's care arrives live", () async {
    final pets = _FakePets(
      initial: _pet(fedAgo: const Duration(days: 2), name: 'mochi'),
    );
    final viewModel = _viewModel(pets);
    await viewModel.init();

    var notified = 0;
    viewModel.addListener(() => notified++);

    pets.pushFromPartner(_pet(name: 'mochi', outfit: PetOutfit.scarf));

    expect(notified, 1);
    expect(viewModel.state.hunger, PetHunger.full);
    expect(viewModel.pet?.outfit, PetOutfit.scarf);
  });

  test("another couple's pet is ignored even if it reaches us", () async {
    final pets = _FakePets(initial: _pet(name: 'mochi'));
    final viewModel = _viewModel(pets);
    await viewModel.init();

    pets.pushFromPartner(_pet(name: 'not ours', coupleId: 'couple2'));

    expect(viewModel.pet?.name, 'mochi');
  });

  test('actions on a pet that never loaded are no-ops, not crashes', () async {
    final pets = _FakePets(initial: null);
    final viewModel = _viewModel(pets);
    await viewModel.init();

    await viewModel.feed();
    await viewModel.cuddle();
    await viewModel.rename('x');
    await viewModel.dress(variant: PetVariant.cat, outfit: PetOutfit.bow);

    expect(pets.calls, ['getOrCreate']);
    expect(viewModel.error, isNull);
  });

  group('loadHistory (the "story")', () {
    test('lazily fetches once, then reuses the cached list', () async {
      final pets = _FakePets(initial: _pet())
        ..events = [
          PetEvent(
            id: 'ev1',
            coupleId: 'couple1',
            userId: 'userA',
            type: 'feed',
            created: _now,
          ),
        ];
      final viewModel = _viewModel(pets);
      await viewModel.init();

      expect(viewModel.historyLoaded, isFalse);
      expect(viewModel.history, isEmpty);
      expect(pets.calls, ['getOrCreate']);

      await viewModel.loadHistory();

      expect(viewModel.historyLoaded, isTrue);
      expect(viewModel.historyLoading, isFalse);
      expect(viewModel.history, hasLength(1));
      expect(pets.calls, ['getOrCreate', 'fetchEvents']);

      // Opening the story again does not refetch.
      await viewModel.loadHistory();
      expect(pets.calls, ['getOrCreate', 'fetchEvents']);
    });

    test('a failed fetch leaves history empty and retryable', () async {
      final pets = _FakePets(initial: _pet())..failEvents = true;
      final viewModel = _viewModel(pets);
      await viewModel.init();

      await viewModel.loadHistory();

      expect(viewModel.historyLoaded, isFalse);
      expect(viewModel.historyLoading, isFalse);
      expect(viewModel.history, isEmpty);

      // A later retry (e.g. reopening the dialog) can still succeed.
      pets.failEvents = false;
      await viewModel.loadHistory();
      expect(viewModel.historyLoaded, isTrue);
    });

    test('an unpaired user gets no history and no fetch attempt', () async {
      final pets = _FakePets(initial: _pet());
      final viewModel = _viewModel(pets, couple: null);
      await viewModel.init();

      await viewModel.loadHistory();

      expect(pets.calls, isEmpty);
      expect(viewModel.historyLoaded, isFalse);
      expect(viewModel.history, isEmpty);
    });
  });
}
