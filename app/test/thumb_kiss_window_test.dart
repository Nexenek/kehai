import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/data/repositories/touch_repository.dart';
import 'package:couples_app/domain/models/touch_point.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/thumbkiss/thumb_kiss_view_model.dart';
import 'package:couples_app/ui/features/thumbkiss/thumb_kiss_window.dart';

/// Never actually subscribes over the network — [ThumbKissWindow]'s tests
/// drive state by calling the view model's own methods and by pushing
/// touches straight through [emit], same fake shape as
/// thumb_kiss_view_model_test.dart's.
class _FakeTouchRepository extends TouchRepository {
  _FakeTouchRepository() : super(PocketBase('http://127.0.0.1:1'));

  void Function(TouchPoint touch)? _onChange;

  @override
  Future<void> send({
    required String coupleId,
    required String userId,
    required double x,
    required double y,
  }) async {}

  @override
  Future<UnsubscribeFunc> subscribe(
    void Function(TouchPoint touch) onChange,
  ) async {
    _onChange = onChange;
    return () async {};
  }

  void emit(TouchPoint touch) => _onChange?.call(touch);
}

AuthRepository _loggedInAuthRepository() {
  final pb = PocketBase('https://example.invalid');
  pb.authStore.save(
    'tok',
    RecordModel({
      'id': 'me',
      'collectionId': 'c',
      'collectionName': 'users',
      'couple': 'couple1',
    }),
  );
  return AuthRepository(pb);
}

void main() {
  late _FakeTouchRepository repository;
  late ThumbKissViewModel viewModel;

  setUp(() async {
    repository = _FakeTouchRepository();
    viewModel = ThumbKissViewModel(
      authRepository: _loggedInAuthRepository(),
      touchRepository: repository,
    );
    await viewModel.init();
  });

  tearDown(() {
    viewModel.dispose();
  });

  Future<void> pumpWindow(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ThumbKissWindow(viewModel: viewModel)),
    ),
  );

  testWidgets('shows the waiting hint and the title in the idle state', (
    tester,
  ) async {
    await pumpWindow(tester);

    expect(find.text(AppStrings.thumbKissTitle), findsOneWidget);
    expect(find.text(AppStrings.thumbKissHint), findsOneWidget);
    expect(find.text(AppStrings.thumbKissMetMessage), findsNothing);
    expect(find.byKey(const Key('thumb-kiss-canvas')), findsOneWidget);
  });

  testWidgets('still shows the hint once the partner is touching but not met', (
    tester,
  ) async {
    await pumpWindow(tester);

    repository.emit(
      TouchPoint(userId: 'partner', x: 0.1, y: 0.1, at: DateTime.now()),
    );
    await tester.pump();

    expect(find.text(AppStrings.thumbKissHint), findsOneWidget);
    expect(find.text(AppStrings.thumbKissMetMessage), findsNothing);
  });

  testWidgets('switches to the met message once both fingertips overlap', (
    tester,
  ) async {
    await pumpWindow(tester);

    viewModel.onTouchMove(const Offset(0.5, 0.5));
    repository.emit(
      TouchPoint(userId: 'partner', x: 0.5, y: 0.5, at: DateTime.now()),
    );
    await tester.pump();

    expect(find.text(AppStrings.thumbKissMetMessage), findsOneWidget);
    expect(find.text(AppStrings.thumbKissHint), findsNothing);

    // Un-meet before the test ends so the sparkle ticker (started on the met
    // edge) stops rather than leaking into the next test.
    viewModel.onTouchMove(const Offset(0.05, 0.05));
    await tester.pump();
  });

  testWidgets('drops back to the hint once the thumbs separate again', (
    tester,
  ) async {
    await pumpWindow(tester);

    viewModel.onTouchMove(const Offset(0.5, 0.5));
    repository.emit(
      TouchPoint(userId: 'partner', x: 0.5, y: 0.5, at: DateTime.now()),
    );
    await tester.pump();
    expect(find.text(AppStrings.thumbKissMetMessage), findsOneWidget);

    viewModel.onTouchMove(const Offset(0.05, 0.05));
    await tester.pump();

    expect(find.text(AppStrings.thumbKissHint), findsOneWidget);
    expect(find.text(AppStrings.thumbKissMetMessage), findsNothing);

    // Let the sparkle animation controller (started on the met edge) settle
    // so the test doesn't finish with a dangling ticker.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('always shows the latency-expectations line', (tester) async {
    await pumpWindow(tester);
    expect(find.text(AppStrings.thumbKissLatencyHint), findsOneWidget);
  });
}
