import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/kehai_tray.dart';
import 'package:couples_app/data/services/update_service.dart';
import 'package:couples_app/data/services/updates/update_installer.dart';
import 'package:couples_app/data/services/updates/update_release.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';

String _releaseJson(String tag) =>
    '''
{
  "tag_name": "$tag",
  "body": "notes for $tag",
  "assets": [
    {
      "name": "kehai-linux-x64-${normalizeVersion(tag)}.tar.gz",
      "browser_download_url": "https://example.test/kehai.tar.gz",
      "size": 48000000
    }
  ]
}
''';

/// A stand-in for the platform half: records what it was asked to do,
/// and can be told to fail at either step.
class _FakeInstaller implements UpdateInstaller {
  _FakeInstaller({this.target = UpdateTarget.linux});

  @override
  final UpdateTarget target;

  int cleanUps = 0;
  int stages = 0;
  int applies = 0;
  int discards = 0;

  Object? stageError;
  Object? applyError;

  /// Progress values the stage step reports before finishing.
  List<double> progressSteps = const [0.5, 1.0];

  /// When set, [stage] hangs on this instead of completing — the "download
  /// still in flight" case.
  Completer<void>? stageGate;

  @override
  Future<UpdateStaging> stage(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    stages++;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    if (stageGate != null) await stageGate!.future;
    if (stageError != null) throw stageError!;
    return const UpdateStaging(
      payloadPath: '/staging/bundle',
      scratchDir: '/staging',
    );
  }

  @override
  Future<void> apply(UpdateStaging staging) async {
    applies++;
    if (applyError != null) throw applyError!;
  }

  @override
  Future<void> cleanUpAfterUpdate() async => cleanUps++;

  @override
  Future<void> discard(UpdateStaging staging) async => discards++;
}

void main() {
  ({UpdateService service, _FakeInstaller installer, List<Uri> fetches}) build({
    String current = '1.0.2',
    String tag = 'v1.0.3',
    Object? fetchError,
    String? body,
    _FakeInstaller? installer,
    bool enabled = true,
  }) {
    final fetches = <Uri>[];
    final fake = installer ?? _FakeInstaller();
    final service = UpdateService(
      installer: fake,
      enabled: enabled,
      currentVersion: () async => current,
      fetch: (url) async {
        fetches.add(url);
        if (fetchError != null) throw fetchError;
        return body ?? _releaseJson(tag);
      },
    );
    return (service: service, installer: fake, fetches: fetches);
  }

  group('when updates are allowed at all', () {
    test('an ordinary debug run never updates — the define is the only way '
        'in', () {
      // The nuance the spec asks for: not a plain kReleaseMode guard, so
      // the feature is testable by hand, but nothing self-updates in a
      // debug build unless somebody explicitly asked for it. A test run is
      // neither release mode nor defined, so:
      expect(UpdateService.updatesEnabled, isFalse);
      expect(kehaiFakeVersion, isEmpty);
    });

    test('a platform with no installer is disabled, whatever the build', () {
      final service = UpdateService(installer: null, enabled: true);
      expect(service.isEnabled, isFalse);
    });

    test('a disabled service does nothing at all', () {
      fakeAsync((async) {
        final t = build(enabled: false);

        t.service.start();
        t.service.reportOnline();
        async.elapse(const Duration(days: 3));

        expect(t.fetches, isEmpty);
        expect(t.installer.cleanUps, 0);
        expect(t.service.stage, UpdateStage.idle);
      });
    });
  });

  group('the launch check', () {
    test('waits for the server rather than firing at start()', () {
      fakeAsync((async) {
        final t = build();

        t.service.start();
        // Kehai autostarts at login; the tailnet often isn't up yet.
        async.elapse(const Duration(days: 2));
        expect(t.fetches, isEmpty);

        t.service.reportOnline();
        async.flushMicrotasks();
        expect(t.fetches, [UpdateService.latestReleaseUrl]);
      });
    });

    test('only the first "we are online" releases it', () {
      fakeAsync((async) {
        final t = build();

        t.service.start();
        t.service.reportOnline();
        t.service.reportOnline();
        t.service.reportOnline();
        async.flushMicrotasks();

        expect(t.fetches, hasLength(1));
      });
    });

    test('start() sweeps up whatever the last update left behind', () {
      final t = build();
      t.service.start();
      expect(t.installer.cleanUps, 1);
      // Idempotent — a second start() is not a second sweep.
      t.service.start();
      expect(t.installer.cleanUps, 1);
    });
  });

  group('checking', () {
    test('a newer release becomes an offer, with its version and notes', () {
      fakeAsync((async) {
        final t = build(current: '1.0.2', tag: 'v1.0.3');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.available);
        expect(t.service.hasUpdate, isTrue);
        expect(t.service.availableVersion, '1.0.3');
        expect(t.service.releaseNotes, contains('v1.0.3'));
      });
    });

    test('the same version, or an older one, is not an offer', () {
      for (final tag in ['v1.0.2', 'v1.0.1']) {
        fakeAsync((async) {
          final t = build(current: '1.0.2', tag: tag);

          t.service.start();
          t.service.reportOnline();
          async.flushMicrotasks();

          expect(t.service.stage, UpdateStage.idle, reason: tag);
          expect(t.service.availableVersion, isNull);
        });
      }
    });

    test('a newer release with no asset for this platform is not an offer', () {
      fakeAsync((async) {
        final t = build(
          installer: _FakeInstaller(target: UpdateTarget.windows),
        );

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        // The canned release only carries the linux tarball.
        expect(t.service.stage, UpdateStage.idle);
      });
    });

    test('then once a day, forever', () {
      fakeAsync((async) {
        final t = build(tag: 'v1.0.2');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        expect(t.fetches, hasLength(1));

        async.elapse(const Duration(hours: 23, minutes: 59));
        expect(t.fetches, hasLength(1));

        async.elapse(const Duration(minutes: 1));
        expect(t.fetches, hasLength(2));

        async.elapse(const Duration(days: 3));
        expect(t.fetches, hasLength(5));

        t.service.stop();
      });
    });

    test('stop() ends the loop', () {
      fakeAsync((async) {
        final t = build(tag: 'v1.0.2');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        t.service.stop();

        async.elapse(const Duration(days: 5));
        expect(t.fetches, hasLength(1));
      });
    });
  });

  group('a check that fails', () {
    test('says nothing when nobody asked — and tries again sooner', () {
      fakeAsync((async) {
        final t = build(fetchError: StateError('no tailnet'));

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        // Quiet: a background failure is a log line, never a chip.
        expect(t.service.stage, UpdateStage.idle);
        expect(t.service.lastCheckError, contains('no tailnet'));

        async.elapse(t.service.retryInterval);
        expect(t.fetches, hasLength(2));

        t.service.stop();
      });
    });

    test('leaves an offer already on screen alone', () {
      fakeAsync((async) {
        var fail = false;
        final service = UpdateService(
          installer: _FakeInstaller(),
          enabled: true,
          currentVersion: () async => '1.0.2',
          fetch: (url) async {
            if (fail) throw StateError('gone');
            return _releaseJson('v1.0.3');
          },
        );

        service.start();
        service.reportOnline();
        async.flushMicrotasks();
        expect(service.stage, UpdateStage.available);

        fail = true;
        async.elapse(service.checkInterval);
        expect(service.stage, UpdateStage.available);
        expect(service.availableVersion, '1.0.3');

        service.dispose();
      });
    });

    test('a manual check is the one that is allowed to show an error', () {
      fakeAsync((async) {
        final t = build(fetchError: StateError('nope'));

        t.service.start();
        unawaited(t.service.checkNow(manual: true));
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.failed);
        expect(t.service.failedStep, UpdateStep.check);
        expect(t.service.failureReason, contains('nope'));

        t.service.stop();
      });
    });

    test('an unreadable body is a failure, not a crash', () {
      fakeAsync((async) {
        final t = build(body: '{"message":"Not Found"}');

        t.service.start();
        unawaited(t.service.checkNow(manual: true));
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.failed);
      });
    });
  });

  group('downloading and applying', () {
    test('one tap runs the whole thing: download, then apply', () {
      fakeAsync((async) {
        final t = build();

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.installer.stages, 1);
        expect(t.installer.applies, 1);
        // Desktop never comes back from apply() — the process is on its
        // way out — so applying is where the state rests.
        expect(t.service.stage, UpdateStage.applying);

        t.service.stop();
      });
    });

    test('progress is reported while it downloads', () {
      fakeAsync((async) {
        final t = build();
        t.installer.progressSteps = const [0.25, 0.5];
        t.installer.stageGate = Completer<void>();

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        final seen = <double>[];
        t.service.addListener(() {
          if (t.service.stage == UpdateStage.downloading) {
            seen.add(t.service.progress);
          }
        });
        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.downloading);
        expect(seen, containsAllInOrder([0.25, 0.5]));

        t.installer.stageGate!.complete();
        async.flushMicrotasks();
        expect(t.service.stage, UpdateStage.applying);

        t.service.stop();
      });
    });

    test('a periodic check while a download is in flight is a no-op', () {
      fakeAsync((async) {
        final t = build();
        t.installer.stageGate = Completer<void>();

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        expect(t.fetches, hasLength(1));

        unawaited(t.service.onTap());
        async.flushMicrotasks();
        expect(t.service.stage, UpdateStage.downloading);

        async.elapse(const Duration(days: 2));
        expect(t.fetches, hasLength(1));
        expect(t.installer.stages, 1);

        t.installer.stageGate!.complete();
        async.flushMicrotasks();
        t.service.stop();
      });
    });

    test('a second tap mid-download starts nothing', () {
      fakeAsync((async) {
        final t = build();
        t.installer.stageGate = Completer<void>();

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        unawaited(t.service.onTap());
        async.flushMicrotasks();
        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.installer.stages, 1);

        t.installer.stageGate!.complete();
        async.flushMicrotasks();
        t.service.stop();
      });
    });
  });

  group('a download or install that fails', () {
    test('lands in failed(download) and never reaches apply — the running '
        'app is untouched', () {
      fakeAsync((async) {
        final t = build();
        t.installer.stageError = StateError('size mismatch');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.failed);
        expect(t.service.failedStep, UpdateStep.download);
        expect(t.service.failureReason, contains('size mismatch'));
        expect(t.installer.applies, 0, reason: 'nothing was ever staged');

        t.service.stop();
      });
    });

    test('retry re-runs the download — not the check', () {
      fakeAsync((async) {
        final t = build();
        t.installer.stageError = StateError('dropped');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        unawaited(t.service.onTap());
        async.flushMicrotasks();
        expect(t.fetches, hasLength(1));

        t.installer.stageError = null;
        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.fetches, hasLength(1), reason: 'the check was fine');
        expect(t.installer.stages, 2);
        expect(t.installer.applies, 1);

        t.service.stop();
      });
    });

    test('an apply failure keeps the good staging and retries the apply', () {
      fakeAsync((async) {
        final t = build();
        t.installer.applyError = StateError('could not spawn helper');

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();
        unawaited(t.service.onTap());
        async.flushMicrotasks();

        expect(t.service.stage, UpdateStage.failed);
        expect(t.service.failedStep, UpdateStep.apply);
        expect(t.installer.discards, 0, reason: 'that download was good');

        unawaited(t.service.onTap());
        async.flushMicrotasks();
        expect(t.installer.applies, 2);

        t.service.stop();
      });
    });

    test('a failed check retries the check', () {
      fakeAsync((async) {
        var fail = true;
        final service = UpdateService(
          installer: _FakeInstaller(),
          enabled: true,
          currentVersion: () async => '1.0.2',
          fetch: (url) async {
            if (fail) throw StateError('nope');
            return _releaseJson('v1.0.3');
          },
        );

        service.start();
        unawaited(service.checkNow(manual: true));
        async.flushMicrotasks();
        expect(service.stage, UpdateStage.failed);

        fail = false;
        unawaited(service.onTap());
        async.flushMicrotasks();
        expect(service.stage, UpdateStage.available);

        service.dispose();
      });
    });
  });

  group('the desktop tray menu', () {
    test('offers a manual check always, and "update to vX.Y.Z" only while '
        'there is one', () {
      fakeAsync((async) {
        final t = build();
        KehaiTray.instance.attachUpdates(t.service);

        List<String?> labels() =>
            KehaiTray.instance.buildMenu().items!.map((i) => i.label).toList();

        expect(labels(), contains(AppStrings.trayCheckUpdates));
        expect(labels(), isNot(contains(AppStrings.trayUpdate('1.0.3'))));
        // "quit for real" is still the last word.
        expect(labels().last, AppStrings.trayQuit);

        t.service.start();
        t.service.reportOnline();
        async.flushMicrotasks();

        expect(labels(), contains(AppStrings.trayUpdate('1.0.3')));

        t.service.stop();
      });
    });
  });
}
