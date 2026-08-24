import 'dart:math' as math;

import 'package:flutter/material.dart';
// Types only — no plugin call happens at import time, which is what lets a
// widget test render this screen with null renderers and no native side.
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCVideoRenderer, RTCVideoView, RTCVideoViewObjectFit;

import '../../../data/services/portal/portal_engine.dart';
import '../../../data/services/prefs_service.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/win_glyph_button.dart';
import 'portal_auto_accept_dialog.dart';
import 'portal_curtain_painter.dart';

/// The curtain: a full-screen, painted-pixel window between two homes
/// (kb/features.md "Portal mode"). Talks to [PortalCallSurface], not
/// [PortalEngine] directly — see that interface's own note — so nothing
/// here can reach past it to open a camera. Every path from idle to
/// connected and back goes through [PortalCallSurface.knock]/`accept`/
/// `decline`/`hangUp`; the curtain only ever *reflects* [PortalCallSurface
/// .state], it never decides it.
///
/// The camera-trust rule made visual: the drapes are open — and the remote
/// [RTCVideoView] paints at all — if and only if
/// `engine.state == PortalState.connected`. There is no other path to a
/// visible video frame anywhere in this file, which is what makes "the
/// curtain visual must never suggest camera-on while the engine says
/// otherwise" true by construction rather than by care.
class PortalCallScreen extends StatefulWidget {
  const PortalCallScreen({
    super.key,
    required this.engine,
    required this.prefs,
    this.partnerDark = _alwaysBright,
    this.partnerDarkListenable,
  });

  final PortalCallSurface engine;
  final PrefsService prefs;

  /// Whether to lead with [AppStrings.portalDarkWindow] instead of the
  /// knock button being primary — the partner is asleep, or every device
  /// of theirs is offline. Read fresh on every rebuild rather than snapshot
  /// once; see [partnerDarkListenable].
  final bool Function() partnerDark;

  /// What to listen to so [partnerDark] gets re-read as the partner's
  /// ambient state changes while this screen sits open — typically the
  /// same `HomeViewModel` the caller already has. Null (every test, and the
  /// auto-accept-triggered push, where a knock already proves they're not
  /// dark) just means [partnerDark] is read once and never again.
  final Listenable? partnerDarkListenable;

  static bool _alwaysBright() => false;

  @override
  State<PortalCallScreen> createState() => _PortalCallScreenState();
}

class _PortalCallScreenState extends State<PortalCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  void _updateSway({required bool idle, required bool reducedMotion}) {
    final shouldRun = idle && !reducedMotion;
    if (shouldRun && !_sway.isAnimating) {
      _sway.repeat(reverse: true);
    } else if (!shouldRun && _sway.isAnimating) {
      _sway.stop();
      _sway.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final darkListenable = widget.partnerDarkListenable;
    final listenable = darkListenable == null
        ? widget.engine
        : Listenable.merge([widget.engine, darkListenable]);

    return Scaffold(
      backgroundColor: colors.ink,
      // No visible title bar — the curtain fills the whole window on
      // purpose — so a screen reader needs this said explicitly instead of
      // reading it off chrome.
      body: Semantics(
        container: true,
        label: AppStrings.portalTitle,
        child: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final state = widget.engine.state;
            _updateSway(
              idle: state == PortalState.idle,
              reducedMotion: MediaQuery.disableAnimationsOf(context),
            );
            return AnimatedBuilder(
              animation: _sway,
              builder: (context, _) => _PortalCurtainBody(
                state: state,
                lastError: widget.engine.lastError,
                localRenderer: widget.engine.localRenderer,
                remoteRenderer: widget.engine.remoteRenderer,
                partnerDark: widget.partnerDark(),
                swayFraction: _sway.value,
                onKnock: widget.engine.knock,
                onAccept: widget.engine.accept,
                onDecline: widget.engine.decline,
                onCancelKnock: widget.engine.hangUp,
                onHangUp: widget.engine.hangUp,
                onOpenSettings: () =>
                    showPortalAutoAcceptDialog(context, prefs: widget.prefs),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PortalCurtainBody extends StatelessWidget {
  const _PortalCurtainBody({
    required this.state,
    required this.lastError,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.partnerDark,
    required this.swayFraction,
    required this.onKnock,
    required this.onAccept,
    required this.onDecline,
    required this.onCancelKnock,
    required this.onHangUp,
    required this.onOpenSettings,
  });

  final PortalState state;
  final String? lastError;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;
  final bool partnerDark;
  final double swayFraction;
  final VoidCallback onKnock;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancelKnock;
  final VoidCallback onHangUp;
  final VoidCallback onOpenSettings;

  bool get _open => state == PortalState.connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final drapeDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 650);
    // ±3px at the loose edge — "subtle idle sway", never anything a glance
    // could mistake for the curtain opening.
    final sway = math.sin(swayFraction * math.pi) * 3;

    return SafeArea(
      child: Stack(
        children: [
          // Always laid out, only ever paint-visible once the drapes have
          // actually parted (`_open`) — see the class doc.
          Positioned.fill(
            child: _RemoteLayer(renderer: remoteRenderer, open: _open),
          ),
          Positioned.fill(
            child: Row(
              // Loose cross-axis constraints (Row's default) would leave
              // each drape's CustomPaint with no bounded height to size
              // itself to — stretch so both halves fill the Stack exactly.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedSlide(
                    key: const Key('portal-drape-left'),
                    duration: drapeDuration,
                    curve: Curves.easeInOutCubic,
                    offset: _open ? const Offset(-1, 0) : Offset.zero,
                    child: CustomPaint(
                      painter: PortalDrapePainter(
                        fill: colors.accent2,
                        pleatShade: colors.chromeAlt,
                        valance: colors.accent,
                        ink: colors.ink,
                        rightSide: false,
                        sway: _open ? 0 : sway,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSlide(
                    key: const Key('portal-drape-right'),
                    duration: drapeDuration,
                    curve: Curves.easeInOutCubic,
                    offset: _open ? const Offset(1, 0) : Offset.zero,
                    child: CustomPaint(
                      painter: PortalDrapePainter(
                        fill: colors.accent2,
                        pleatShade: colors.chromeAlt,
                        valance: colors.accent,
                        ink: colors.ink,
                        rightSide: true,
                        sway: _open ? 0 : sway,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                WinGlyphButton(
                  glyph: '◂',
                  tooltip: AppStrings.back,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                WinGlyphButton(
                  glyph: '✧',
                  tooltip: AppStrings.portalAutoAcceptTitle,
                  onTap: onOpenSettings,
                ),
              ],
            ),
          ),
          if (!_open)
            Positioned.fill(
              child: _CurtainContent(
                state: state,
                lastError: lastError,
                partnerDark: partnerDark,
                onKnock: onKnock,
                onAccept: onAccept,
                onDecline: onDecline,
                onCancelKnock: onCancelKnock,
              ),
            ),
          if (_open) ...[
            Positioned(
              right: 12,
              bottom: 12,
              width: 120,
              height: 90,
              child: _LocalPreview(renderer: localRenderer),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: PixelButton(
                  key: const Key('portal-hang-up'),
                  label: AppStrings.portalHangUp,
                  onPressed: onHangUp,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The content shown over the closed curtain — everything but `connected`
/// and `connecting`'s bare spinner text.
class _CurtainContent extends StatelessWidget {
  const _CurtainContent({
    required this.state,
    required this.lastError,
    required this.partnerDark,
    required this.onKnock,
    required this.onAccept,
    required this.onDecline,
    required this.onCancelKnock,
  });

  final PortalState state;
  final String? lastError;
  final bool partnerDark;
  final VoidCallback onKnock;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancelKnock;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PortalState.idle => _IdleContent(
        lastError: lastError,
        partnerDark: partnerDark,
        onKnock: onKnock,
      ),
      PortalState.knocking => _KnockingContent(onCancel: onCancelKnock),
      PortalState.knocked => _KnockedContent(
        onAccept: onAccept,
        onDecline: onDecline,
      ),
      PortalState.connecting => const _ConnectingContent(),
      // Nothing to press: the teardown is already running and any button
      // here would be a lie about what's happening.
      PortalState.closing => const SizedBox.shrink(),
      PortalState.connected => const SizedBox.shrink(),
    };
  }
}

class _IdleContent extends StatelessWidget {
  const _IdleContent({
    required this.lastError,
    required this.partnerDark,
    required this.onKnock,
  });

  final String? lastError;
  final bool partnerDark;
  final VoidCallback onKnock;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lastError != null) ...[
                BevelBox(
                  color: colors.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    lastError!,
                    key: const Key('portal-error'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body2.copyWith(color: colors.accent),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (partnerDark) ...[
                Text(
                  AppStrings.portalDarkWindow,
                  key: const Key('portal-dark-window'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body2.copyWith(color: colors.surface),
                ),
                const SizedBox(height: 14),
              ],
              Opacity(
                opacity: partnerDark ? 0.55 : 1,
                child: PixelButton(
                  key: const Key('portal-knock-button'),
                  label: AppStrings.portalKnockButton,
                  primary: !partnerDark,
                  onPressed: onKnock,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: Center(
            child: Text(
              AppStrings.portalCurtainHint,
              style: AppTextStyles.caption.copyWith(color: colors.surface),
            ),
          ),
        ),
      ],
    );
  }
}

class _KnockingContent extends StatelessWidget {
  const _KnockingContent({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pulse(
            child: Text(
              AppStrings.portalKnocking,
              style: AppTextStyles.body1.copyWith(color: colors.surface),
            ),
          ),
          const SizedBox(height: 18),
          PixelButton(
            key: const Key('portal-cancel-knock'),
            label: AppStrings.portalHangUp,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _KnockedContent extends StatelessWidget {
  const _KnockedContent({required this.onAccept, required this.onDecline});

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.portalKnockedTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading.copyWith(color: colors.surface),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelButton(
                key: const Key('portal-accept'),
                label: AppStrings.portalAccept,
                primary: true,
                onPressed: onAccept,
              ),
              const SizedBox(width: 12),
              PixelButton(
                key: const Key('portal-decline'),
                label: AppStrings.portalDecline,
                onPressed: onDecline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectingContent extends StatelessWidget {
  const _ConnectingContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: _Pulse(
        child: Text(
          AppStrings.portalConnecting,
          style: AppTextStyles.body1.copyWith(color: colors.surface),
        ),
      ),
    );
  }
}

/// A slow opacity pulse — the one orchestrated moment these two "waiting"
/// states get (design-language.md's "smooth ≠ busy"). Instant (no pulse) if
/// the platform asked for reduced motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.55,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// The remote video — full-bleed, drawn behind the drapes always, but only
/// ever painted with real pixels once [open] is true.
class _RemoteLayer extends StatelessWidget {
  const _RemoteLayer({required this.renderer, required this.open});

  final RTCVideoRenderer? renderer;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final view = renderer;
    if (!open || view == null) {
      return ColoredBox(color: colors.ink);
    }
    return RTCVideoView(
      view,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

/// The local preview — a small pixel-framed corner card, only ever shown
/// once connected.
class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.renderer});

  final RTCVideoRenderer? renderer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final view = renderer;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.ink, width: 2),
      ),
      child: view == null
          ? null
          : RTCVideoView(
              view,
              // A preview of yourself reads as a mirror or it reads as
              // wrong; nobody has ever wanted the unmirrored version.
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
    );
  }
}
