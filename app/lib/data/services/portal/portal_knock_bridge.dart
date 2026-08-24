import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../notifications/notification_hub.dart';
import '../prefs_service.dart';
import 'portal_engine.dart';

/// Is [hour] inside the quiet-hours auto-accept window? Pure, so the
/// midnight-wrap case (`fromHour > toHour`, e.g. 22 → 6) gets a real unit
/// test instead of being trusted by inspection.
///
/// [fromHour] == [toHour] reads as "the whole day" rather than "never" —
/// the natural reading of a wrapping range that goes all the way around
/// back to where it started, and the one that can't silently defeat the
/// toggle above it (a same-hour range some UI accident produced still
/// means "always", not a range that quietly does nothing).
bool shouldAutoAccept({
  required bool enabled,
  required int fromHour,
  required int toHour,
  required int hour,
}) {
  if (!enabled) return false;
  if (fromHour == toHour) return true;
  if (fromHour < toHour) return hour >= fromHour && hour < toHour;
  // Wraps past midnight: "inside" is everything from `from` to 24, plus
  // everything from 0 up to `to`.
  return hour >= fromHour || hour < toHour;
}

/// Watches a live [PortalCallSurface] for an incoming knock and does the two
/// things a knock needs done on whichever isolate can actually *show*
/// someone the curtain: raise the same notification the closed-app (FGS
/// isolate) path raises — kb/roadmap.md Phase 7's "notify while the app is
/// closed" also covers "notify while the app is open but you're looking at
/// something else" — and, quiet-hours auto-accept, let the curtain open
/// itself.
///
/// Deliberately UI-isolate only, and deliberately not the thing that
/// touches media: this class never calls anything but
/// [PortalCallSurface.accept] — the camera-trust rule stays entirely
/// [PortalEngine]'s job. [bringToFront] is a plain callback rather than a
/// Navigator/BuildContext dependency so this stays a data-layer class with
/// no widget imports; the UI layer (home_screen.dart, "wherever pings do
/// it") wires it once.
class PortalKnockBridge {
  PortalKnockBridge({
    required this.engine,
    required this.notifications,
    required this.prefs,
    required this.isDesktop,
    required this.isAppForeground,
    @visibleForTesting DateTime Function()? now,
  }) : _now = now ?? clock.now;

  final PortalCallSurface engine;
  final KehaiNotifications notifications;
  final PrefsService prefs;
  final bool Function() isDesktop;
  final bool Function() isAppForeground;
  final DateTime Function() _now;

  /// Brings the curtain to the front so an auto-accepted call has somewhere
  /// to show up. Left unset (a no-op) is safe — auto-accept just won't push
  /// a route, and [PortalCallSurface.accept] still runs, so the engine
  /// itself is never left half-answered.
  ///
  /// Desktop: expected to expand the window and push the curtain route.
  /// Android: this is only ever invoked while the app is already
  /// foregrounded (see [_maybeAutoAccept]) — starting an activity from the
  /// background isn't attempted anywhere in this class, because it can't
  /// be: a backgrounded Android app has no window to bring forward, full
  /// stop.
  VoidCallback? bringToFront;

  PortalState _lastState = PortalState.idle;
  bool _started = false;

  /// Starts listening. Idempotent, same reasoning as [PortalEngine.init].
  void start() {
    if (_started) return;
    _started = true;
    _lastState = engine.state;
    engine.addListener(_onEngineChange);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    engine.removeListener(_onEngineChange);
  }

  void _onEngineChange() {
    final state = engine.state;
    final freshKnock =
        state == PortalState.knocked && _lastState != PortalState.knocked;
    _lastState = state;
    if (!freshKnock) return;

    // The engine only ever reaches `knocked` from a knock it already
    // decided was fresh and genuinely the partner's (self-echo dropped at
    // the repository, staleness checked in `_handle` — see
    // isPortalSignalFresh) — nothing left to re-check here.
    final partnerId = engine.partnerId ?? '';
    notifications.report(() => notifications.reportKnock(fromId: partnerId));
    _maybeAutoAccept();
  }

  void _maybeAutoAccept() {
    if (engine.state != PortalState.knocked) return;
    final should = shouldAutoAccept(
      enabled: prefs.portalAutoAcceptEnabled,
      fromHour: prefs.portalAutoAcceptFromHour,
      toHour: prefs.portalAutoAcceptToHour,
      hour: _now().hour,
    );
    if (!should) return;
    // Android: never from the background — see [bringToFront]'s doc.
    if (!isDesktop() && !isAppForeground()) return;
    bringToFront?.call();
    unawaited(engine.accept());
  }
}
