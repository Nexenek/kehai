import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/touch_repository.dart';
import 'package:couples_app/domain/models/touch_point.dart';
import 'package:couples_app/ui/features/thumbkiss/thumb_kiss_view_model.dart';

/// Records every `send` call instead of hitting the network, and exposes
/// [emit] so a test can push a partner touch straight into whatever
/// callback [ThumbKissViewModel.init] registered — same shape as
/// `_RecordingDeviceRepository` in heartbeat_presence_fields_test.dart.
class _FakeTouchRepository extends TouchRepository {
  _FakeTouchRepository() : super(PocketBase('http://127.0.0.1:1'));

  final sent = <Map<String, dynamic>>[];
  void Function(TouchPoint touch)? _onChange;

  @override
  Future<void> send({
    required String coupleId,
    required String userId,
    required double x,
    required double y,
  }) async {
    sent.add({'couple': coupleId, 'user': userId, 'x': x, 'y': y});
  }

  @override
  Future<UnsubscribeFunc> subscribe(
    void Function(TouchPoint touch) onChange,
  ) async {
    _onChange = onChange;
    return () async {};
  }

  void emit(TouchPoint touch) => _onChange?.call(touch);
}

AuthRepository _loggedInAuthRepository({
  String id = 'me',
  String couple = 'couple1',
}) {
  final pb = PocketBase('https://example.invalid');
  pb.authStore.save(
    'tok',
    RecordModel({
      'id': id,
      'collectionId': 'c',
      'collectionName': 'users',
      'couple': couple,
    }),
  );
  return AuthRepository(pb);
}

void main() {
  late _FakeTouchRepository repository;
  late AuthRepository authRepository;
  late ThumbKissViewModel viewModel;
  late int metCount;

  setUp(() async {
    repository = _FakeTouchRepository();
    authRepository = _loggedInAuthRepository();
    metCount = 0;
    viewModel = ThumbKissViewModel(
      authRepository: authRepository,
      touchRepository: repository,
      onMet: () => metCount++,
    );
    await viewModel.init();
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('the first touch of a press sends immediately', () {
    viewModel.onTouchMove(const Offset(0.4, 0.4));

    expect(repository.sent, hasLength(1));
    expect(repository.sent.single['couple'], 'couple1');
    expect(repository.sent.single['user'], 'me');
    expect(repository.sent.single['x'], 0.4);
    expect(repository.sent.single['y'], 0.4);
    expect(viewModel.myTouch, const Offset(0.4, 0.4));
  });

  test('rapid successive moves are throttled', () {
    viewModel.onTouchMove(const Offset(0.1, 0.1));
    viewModel.onTouchMove(const Offset(0.11, 0.11));
    viewModel.onTouchMove(const Offset(0.12, 0.12));

    // Only the first (immediate) send goes through; the throttle window
    // (250ms) hasn't elapsed for the rest.
    expect(repository.sent, hasLength(1));
    // But local rendering still tracks the latest position immediately.
    expect(viewModel.myTouch, const Offset(0.12, 0.12));
  });

  test('lifting the thumb clears my local touch without sending anything', () {
    viewModel.onTouchMove(const Offset(0.5, 0.5));
    final sentBefore = repository.sent.length;

    viewModel.onTouchEnd();

    expect(viewModel.myTouch, isNull);
    expect(repository.sent, hasLength(sentBefore));
  });

  test('a partner touch becomes visible when fresh', () {
    repository.emit(
      TouchPoint(userId: 'partner', x: 0.6, y: 0.6, at: DateTime.now()),
    );

    expect(viewModel.partnerTouch?.offset, const Offset(0.6, 0.6));
    expect(viewModel.partnerVisible, isTrue);
  });

  test('a stale partner touch is not visible', () {
    repository.emit(
      TouchPoint(
        userId: 'partner',
        x: 0.6,
        y: 0.6,
        at: DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );

    expect(viewModel.partnerVisible, isFalse);
  });

  test('an echo of my own touch id is ignored', () {
    repository.emit(TouchPoint(userId: 'me', x: 0.2, y: 0.2, at: DateTime.now()));
    expect(viewModel.partnerTouch, isNull);
  });

  test('two fresh, close-together touches trigger the met state once', () {
    viewModel.onTouchMove(const Offset(0.5, 0.5));
    expect(viewModel.isMet, isFalse);
    expect(metCount, 0);

    repository.emit(
      TouchPoint(userId: 'partner', x: 0.52, y: 0.5, at: DateTime.now()),
    );

    expect(viewModel.isMet, isTrue);
    expect(metCount, 1);

    // Staying met (another close-by update) must not re-fire onMet.
    repository.emit(
      TouchPoint(userId: 'partner', x: 0.53, y: 0.5, at: DateTime.now()),
    );
    expect(metCount, 1);
  });

  test('moving apart again clears the met state', () {
    viewModel.onTouchMove(const Offset(0.5, 0.5));
    repository.emit(
      TouchPoint(userId: 'partner', x: 0.5, y: 0.5, at: DateTime.now()),
    );
    expect(viewModel.isMet, isTrue);

    viewModel.onTouchMove(const Offset(0.9, 0.9));
    expect(viewModel.isMet, isFalse);
  });

  test('far-apart touches never trigger met', () {
    viewModel.onTouchMove(const Offset(0.0, 0.0));
    repository.emit(
      TouchPoint(userId: 'partner', x: 1.0, y: 1.0, at: DateTime.now()),
    );

    expect(viewModel.isMet, isFalse);
    expect(metCount, 0);
  });

  test('no couple id means touches are never sent', () {
    final soloAuth = AuthRepository(PocketBase('https://example.invalid'));
    final soloRepository = _FakeTouchRepository();
    final soloViewModel = ThumbKissViewModel(
      authRepository: soloAuth,
      touchRepository: soloRepository,
    );

    soloViewModel.onTouchMove(const Offset(0.3, 0.3));

    expect(soloRepository.sent, isEmpty);
    soloViewModel.dispose();
  });
}
