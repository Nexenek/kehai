import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/connectivity_monitor.dart';

/// A scriptable stand-in for `pb.health.check()`: each probe consults
/// [answer] for what this attempt should do. Records how many times it was
/// asked, so a test can assert on cadence rather than only on state.
class _Server {
  _Server({this.up = true});

  /// Whether a probe issued right now completes (true) or throws (false).
  bool up;

  /// When set, a probe neither completes nor throws — it just hangs, which
  /// is what a server that has vanished off the tailnet actually does.
  bool hang = false;

  int probes = 0;

  Future<void> check() {
    probes++;
    if (hang) return Completer<void>().future;
    if (up) return Future<void>.value();
    return Future<void>.error(StateError('down'));
  }
}

void main() {
  ({ConnectivityMonitor monitor, _Server server, List<bool> changes}) build({
    bool serverUp = true,
    bool online = true,
  }) {
    final server = _Server(up: serverUp);
    final changes = <bool>[];
    final monitor = ConnectivityMonitor(
      probe: server.check,
      onChanged: changes.add,
      online: online,
    );
    return (monitor: monitor, server: server, changes: changes);
  }

  group('starting up', () {
    test('does nothing at all until start() is called', () {
      fakeAsync((async) {
        final t = build();

        async.elapse(const Duration(minutes: 10));

        expect(t.server.probes, 0);
        expect(t.monitor.isRunning, isFalse);
      });
    });

    test('probes immediately on start — the boot state is only a guess', () {
      fakeAsync((async) {
        final t = build(serverUp: false);

        t.monitor.start();
        async.flushMicrotasks();

        expect(t.server.probes, 1);
        expect(t.monitor.isOnline, isFalse);
        expect(t.changes, [false]);
      });
    });

    test('a healthy start reports nothing — online was already the guess', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();

        expect(t.monitor.isOnline, isTrue);
        expect(t.changes, isEmpty);
      });
    });

    test('start() twice is one loop, not two', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        t.monitor.start();
        async.elapse(ConnectivityMonitor.onlineInterval * 3);

        // One immediate probe plus one per interval — never doubled.
        expect(t.server.probes, 4);
      });
    });
  });

  group('the two cadences', () {
    test('online: one probe per onlineInterval, and only then', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();
        expect(t.server.probes, 1);

        async.elapse(ConnectivityMonitor.onlineInterval - oneSecond);
        expect(t.server.probes, 1);

        async.elapse(oneSecond);
        expect(t.server.probes, 2);
      });
    });

    test('offline: one probe per offlineInterval — the way back is short', () {
      fakeAsync((async) {
        final t = build(serverUp: false);

        t.monitor.start();
        async.flushMicrotasks();
        expect(t.server.probes, 1);

        async.elapse(ConnectivityMonitor.offlineInterval - oneSecond);
        expect(t.server.probes, 1);

        async.elapse(oneSecond);
        expect(t.server.probes, 2);
      });
    });

    test('the cadence switches the moment the state does', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();
        expect(t.monitor.interval, ConnectivityMonitor.onlineInterval);

        t.server.up = false;
        async.elapse(ConnectivityMonitor.onlineInterval);
        expect(t.monitor.isOnline, isFalse);
        expect(t.monitor.interval, ConnectivityMonitor.offlineInterval);

        // Now on the fast schedule: the next probe is 10s away, not 60.
        final before = t.server.probes;
        async.elapse(ConnectivityMonitor.offlineInterval);
        expect(t.server.probes, before + 1);
      });
    });
  });

  group('state transitions', () {
    test('reports each flip once, not once per probe', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();

        t.server.up = false;
        async.elapse(ConnectivityMonitor.onlineInterval);
        async.elapse(ConnectivityMonitor.offlineInterval * 3);
        expect(t.changes, [false]);

        t.server.up = true;
        async.elapse(ConnectivityMonitor.offlineInterval);
        async.elapse(ConnectivityMonitor.onlineInterval * 2);
        expect(t.changes, [false, true]);
        expect(t.monitor.isOnline, isTrue);
      });
    });

    test('the offline→online flip is what a regain hook hangs off', () {
      fakeAsync((async) {
        // The autostart-at-login case: built and started while the tailnet
        // is still coming up.
        final t = build(serverUp: false);
        var regained = 0;
        final monitor = ConnectivityMonitor(
          probe: t.server.check,
          onChanged: (online) {
            if (online) regained++;
          },
        );

        monitor.start();
        async.elapse(ConnectivityMonitor.offlineInterval * 2);
        expect(monitor.isOnline, isFalse);
        expect(regained, 0);

        t.server.up = true;
        async.elapse(ConnectivityMonitor.offlineInterval);
        expect(regained, 1);

        // And it doesn't keep firing while the connection simply stays up.
        async.elapse(ConnectivityMonitor.onlineInterval * 5);
        expect(regained, 1);

        monitor.dispose();
      });
    });
  });

  group('a probe that never answers', () {
    test('counts as offline after probeTimeout, not never', () {
      fakeAsync((async) {
        final t = build();
        t.server.hang = true;

        t.monitor.start();
        async.elapse(ConnectivityMonitor.probeTimeout - oneSecond);
        expect(t.monitor.isOnline, isTrue); // still waiting, not yet a miss

        async.elapse(oneSecond);
        expect(t.monitor.isOnline, isFalse);
        expect(t.changes, [false]);
      });
    });

    test('a hung probe never stacks up a second one', () {
      fakeAsync((async) {
        final t = build();
        t.server.hang = true;

        t.monitor.start();
        // Two full timeouts plus a fast-cadence gap: one miss, one retry —
        // and nothing overlapping in between.
        async.elapse(ConnectivityMonitor.probeTimeout);
        expect(t.server.probes, 1);

        async.elapse(ConnectivityMonitor.offlineInterval);
        expect(t.server.probes, 2);
      });
    });

    test('checkNow() while a probe is in flight is ignored', () {
      fakeAsync((async) {
        final t = build();
        t.server.hang = true;

        t.monitor.start();
        t.monitor.checkNow();
        t.monitor.checkNow();
        async.flushMicrotasks();

        expect(t.server.probes, 1);
      });
    });
  });

  group('stopping', () {
    test('stop() cancels the loop and leaves the last state alone', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();
        t.monitor.stop();

        final before = t.server.probes;
        async.elapse(const Duration(hours: 1));
        expect(t.server.probes, before);
        expect(t.monitor.isOnline, isTrue); // stopping isn't going offline
        expect(t.monitor.isRunning, isFalse);
      });
    });

    test('a probe that lands after stop() reports nothing and rearms '
        'nothing', () {
      fakeAsync((async) {
        final t = build();
        t.server.hang = true;

        t.monitor.start();
        async.elapse(ConnectivityMonitor.probeTimeout - oneSecond);
        t.monitor.stop();
        async.elapse(const Duration(hours: 1));

        expect(t.changes, isEmpty);
        expect(t.monitor.isOnline, isTrue);
        expect(t.server.probes, 1);
      });
    });

    test('dispose() is stop()', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.start();
        async.flushMicrotasks();
        t.monitor.dispose();

        final before = t.server.probes;
        async.elapse(const Duration(hours: 1));
        expect(t.server.probes, before);
      });
    });
  });

  group('report()', () {
    test('takes an answer the caller already has, without a probe', () {
      fakeAsync((async) {
        // The confirmServer path: the health check just succeeded, so
        // there is nothing to re-ask.
        final t = build(serverUp: false, online: false);

        t.monitor.report(true);
        expect(t.monitor.isOnline, isTrue);
        expect(t.changes, [true]);
        expect(t.server.probes, 0);
      });
    });

    test('reschedules a running loop onto the new cadence', () {
      fakeAsync((async) {
        final t = build(online: false);

        t.monitor.start();
        async.flushMicrotasks();
        // The probe found it up, so we're on the slow schedule already.
        expect(t.changes, [true]);

        t.server.up = false;
        t.monitor.report(false);
        expect(t.changes, [true, false]);

        final before = t.server.probes;
        async.elapse(ConnectivityMonitor.offlineInterval);
        expect(t.server.probes, before + 1);
      });
    });

    test('report() on a stopped monitor records but does not start it', () {
      fakeAsync((async) {
        final t = build();

        t.monitor.report(false);
        expect(t.monitor.isOnline, isFalse);

        async.elapse(const Duration(hours: 1));
        expect(t.server.probes, 0);
      });
    });
  });
}

const oneSecond = Duration(seconds: 1);
