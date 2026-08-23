import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/art_repository.dart';
import 'package:couples_app/data/repositories/auth_repository.dart';
import 'package:couples_app/domain/art_scene.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/core/theme/app_theme.dart';
import 'package:couples_app/ui/features/art/art_layer_dialog.dart';
import 'package:couples_app/ui/features/art/art_scene_view.dart';
import 'package:couples_app/ui/features/art/art_view_model.dart';
import 'package:couples_app/ui/features/art/art_window.dart';

/// A real 1×1 transparent PNG — enough for the upload path's magic-byte gate.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8'
  'AAAAASUVORK5CYII=',
);

final Uint8List _jpeg = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0,
  16,
  74,
  70,
  73,
  70,
  0,
  1,
]);

/// A view model wired to real repositories against a fake base URL — never
/// actually hit, because these tests set state directly instead of calling
/// `init()`.
ArtViewModel _viewModel() {
  final pb = PocketBase('https://example.invalid');
  return ArtViewModel(
    authRepository: AuthRepository(pb),
    artRepository: ArtRepository(pb),
  );
}

ArtLayer _layer(
  String id, {
  ArtSlot slot = ArtSlot.base,
  String name = '',
  Set<String> moods = const {},
  Set<String> ambient = const {},
  bool isDefault = false,
}) => ArtLayer(
  id: id,
  coupleId: '',
  slot: slot,
  name: name.isEmpty ? id : name,
  imageUrl: 'https://example.invalid/api/files/art_layers/$id/l.png',
  conditions: ArtConditions(
    moods: moods,
    ambient: ambient,
    isDefault: isDefault,
  ),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(700, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  group('the manager window', () {
    testWidgets('says plainly when there is no art yet, and still explains '
        'how the layers work', (tester) async {
      final viewModel = _viewModel()..isLoading = false;
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.text(AppStrings.artTitle), findsOneWidget);
      expect(find.text(AppStrings.artEmpty), findsOneWidget);
      expect(find.text(AppStrings.artHowToTitle), findsOneWidget);
      expect(find.textContaining('512×512'), findsOneWidget);
      expect(find.textContaining('Pixelorama'), findsOneWidget);
      // A section per slot, each with an add button and an empty note.
      for (final slot in ArtSlot.values) {
        expect(find.byKey(Key('art-add-${slot.name}')), findsOneWidget);
        expect(find.byKey(Key('art-empty-${slot.name}')), findsOneWidget);
      }
    });

    testWidgets('while loading it says so instead of claiming emptiness', (
      tester,
    ) async {
      final viewModel = _viewModel()..isLoading = true;
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.text(AppStrings.artLoading), findsOneWidget);
      expect(find.text(AppStrings.artEmpty), findsNothing);
    });

    testWidgets('with art but no body layer it says why nothing shows yet', (
      tester,
    ) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..layers = [_layer('hat', slot: ArtSlot.prop)];
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.byKey(const Key('art-base-missing')), findsOneWidget);
      expect(find.byKey(const Key('art-preview-fallback')), findsOneWidget);
      expect(find.byType(ArtSceneView), findsNothing);
    });

    testWidgets('the preview composites the real scene once there is a '
        'body layer', (tester) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..layers = [
          _layer('body', isDefault: true),
          _layer('face', slot: ArtSlot.expression, isDefault: true),
        ];
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.byType(ArtSceneView), findsOneWidget);
      expect(find.byKey(const Key('art-preview-fallback')), findsNothing);
      // Both layers are stacked in the preview canvas.
      expect(
        find.descendant(
          of: find.byType(ArtSceneView),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
      expect(find.byKey(const Key('art-base-missing')), findsNothing);
    });

    testWidgets('picking a different preview mood swaps the composited '
        'layers — the artist checks a condition without waiting for their '
        'partner to feel that way', (tester) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..layers = [
          _layer('awake', isDefault: true),
          _layer('tucked-in', moods: {'sleepy'}),
        ];
      await _pump(tester, ArtWindow(viewModel: viewModel));

      Iterable<Key?> sceneKeys() => tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(ArtSceneView),
              matching: find.byType(Image),
            ),
          )
          .map((image) => image.key);

      expect(sceneKeys(), [const ValueKey('awake')]);

      // The preview's mood row uses the mood labels; 'sleepy' is unique.
      await tester.tap(find.text('sleepy').first);
      await tester.pump();

      expect(sceneKeys(), [const ValueKey('tucked-in')]);
      expect(viewModel.previewMoodId, 'sleepy');
    });

    testWidgets('picking an ambient state feeds the same preview', (
      tester,
    ) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..layers = [
          _layer('body', isDefault: true),
          _layer('headphones', slot: ArtSlot.prop, ambient: {'music'}),
        ];
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.byType(ArtSceneView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ArtSceneView),
          matching: find.byType(Image),
        ),
        findsNWidgets(1),
      );

      await tester.tap(find.text(AppStrings.artAmbientMusic).first);
      await tester.pump();

      expect(viewModel.previewAmbientKind, 'music');
      expect(
        find.descendant(
          of: find.byType(ArtSceneView),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('each drawing shows when it is used, in the artist\'s '
        'words', (tester) async {
      final viewModel = _viewModel()
        ..isLoading = false
        ..layers = [
          _layer('body', name: 'sitting', isDefault: true),
          _layer(
            'face',
            slot: ArtSlot.expression,
            name: 'sleepy eyes',
            moods: {'sleepy'},
            ambient: {'music'},
          ),
        ];
      await _pump(tester, ArtWindow(viewModel: viewModel));

      expect(find.text('sitting'), findsOneWidget);
      expect(find.text('sleepy eyes'), findsOneWidget);
      expect(find.textContaining(AppStrings.artAmbientMusic), findsWidgets);
    });

    testWidgets('the add button opens the add dialog for that slot', (
      tester,
    ) async {
      final viewModel = _viewModel()..isLoading = false;
      await _pump(
        tester,
        ArtWindow(
          viewModel: viewModel,
          filePicker: () async => ArtPickedFile(bytes: _png, name: 'a.png'),
        ),
      );

      await tester.tap(find.byKey(const Key('art-add-outfit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.artAddDialogTitle), findsOneWidget);
      // The dialog names the slot it will drop the drawing into.
      expect(
        find.text(
          '${AppStrings.artSlotOutfit} — ${AppStrings.artSlotOutfitHint}',
        ),
        findsOneWidget,
      );
    });
  });

  group('the add-a-drawing dialog', () {
    Future<void> openAdd(
      WidgetTester tester, {
      required ArtFilePicker picker,
      required Future<bool> Function({
        required String name,
        required ArtConditions conditions,
        required Uint8List bytes,
        required String filename,
      })
      onAdd,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(700, 2400);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddArtLayerDialog(
                  context,
                  slot: ArtSlot.expression,
                  pickFile: picker,
                  onAdd: onAdd,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a picked PNG can be named, conditioned and uploaded', (
      tester,
    ) async {
      String? uploadedName;
      ArtConditions? uploadedConditions;
      Uint8List? uploadedBytes;
      String? uploadedFilename;

      await openAdd(
        tester,
        picker: () async => ArtPickedFile(bytes: _png, name: 'sleepy-eyes.png'),
        onAdd:
            ({
              required name,
              required conditions,
              required bytes,
              required filename,
            }) async {
              uploadedName = name;
              uploadedConditions = conditions;
              uploadedBytes = bytes;
              uploadedFilename = filename;
              return true;
            },
      );

      // Nothing to upload until something is picked.
      final submit = find.byKey(const Key('art-add-submit'));
      expect(submit, findsOneWidget);

      await tester.tap(find.byKey(const Key('art-pick-file')));
      await tester.pumpAndSettle();

      // The filename becomes a sensible default name, so the artist rarely
      // has to type anything at all.
      expect(find.text('sleepy eyes'), findsOneWidget);

      await tester.tap(find.text('sleepy').first);
      await tester.pump();
      await tester.tap(find.byKey(const Key('art-default-toggle')));
      await tester.pump();

      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(uploadedName, 'sleepy eyes');
      expect(uploadedConditions?.moods, {'sleepy'});
      expect(uploadedConditions?.isDefault, isTrue);
      expect(uploadedBytes, _png);
      expect(uploadedFilename, 'sleepy-eyes.png');
      // A successful upload closes the dialog.
      expect(find.text(AppStrings.artAddDialogTitle), findsNothing);
    });

    testWidgets('a JPEG is refused with an explanation, not a 400', (
      tester,
    ) async {
      var uploads = 0;
      await openAdd(
        tester,
        picker: () async => ArtPickedFile(bytes: _jpeg, name: 'photo.png'),
        onAdd:
            ({
              required name,
              required conditions,
              required bytes,
              required filename,
            }) async {
              uploads++;
              return true;
            },
      );

      await tester.tap(find.byKey(const Key('art-pick-file')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('art-dialog-error')), findsOneWidget);
      expect(find.text(AppStrings.artNotPng), findsOneWidget);
      expect(uploads, 0);
    });

    testWidgets('an oversized PNG is refused with the size in plain words', (
      tester,
    ) async {
      final huge = Uint8List(2 * 1024 * 1024 + 10)
        ..setRange(0, 8, _png.sublist(0, 8));

      await openAdd(
        tester,
        picker: () async => ArtPickedFile(bytes: huge, name: 'huge.png'),
        onAdd: ({
          required name,
          required conditions,
          required bytes,
          required filename,
        }) async => true,
      );

      await tester.tap(find.byKey(const Key('art-pick-file')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.artTooBig), findsOneWidget);
    });

    testWidgets('a failed upload says so and keeps the dialog open', (
      tester,
    ) async {
      await openAdd(
        tester,
        picker: () async => ArtPickedFile(bytes: _png, name: 'a.png'),
        onAdd: ({
          required name,
          required conditions,
          required bytes,
          required filename,
        }) async => false,
      );

      await tester.tap(find.byKey(const Key('art-pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('art-add-submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.artUploadFailed), findsOneWidget);
      expect(find.text(AppStrings.artAddDialogTitle), findsOneWidget);
    });
  });

  group('the layer editor', () {
    testWidgets('saves the edited name and conditions, and can delete', (
      tester,
    ) async {
      final layer = _layer('face', slot: ArtSlot.expression, name: 'eyes');
      String? savedName;
      ArtConditions? savedConditions;
      var deleted = 0;

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(700, 2400);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEditArtLayerDialog(
                  context,
                  layer: layer,
                  onSave: (name, conditions) async {
                    savedName = name;
                    savedConditions = conditions;
                  },
                  onDelete: () => deleted++,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('eyes'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('art-name-field')),
        'sleepy eyes',
      );
      await tester.tap(find.text(AppStrings.artAmbientAway).first);
      await tester.pump();
      await tester.tap(find.byKey(const Key('art-layer-save')));
      await tester.pumpAndSettle();

      expect(savedName, 'sleepy eyes');
      expect(savedConditions?.ambient, {'away'});
      expect(deleted, 0);
    });
  });
}
