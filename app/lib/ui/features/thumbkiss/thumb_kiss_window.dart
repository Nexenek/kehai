import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;

import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/retro_window.dart';
import 'thumb_kiss_painter.dart';
import 'thumb_kiss_view_model.dart';

/// The thumb-kiss RetroWindow: a soft square touch area where both
/// partners' fingertips glow when present, and a warm flash + sparkle
/// burst mark the moment they meet (kb/features.md "Thumb-kiss").
///
/// Self-contained, same as `InstantsWindow` this batch — a caller just
/// needs a [ThumbKissViewModel] wired to real repositories; the coordinator
/// wires this into the home tray/layout separately.
class ThumbKissWindow extends StatefulWidget {
  const ThumbKissWindow({super.key, required this.viewModel, this.onClose});

  final ThumbKissViewModel viewModel;
  final VoidCallback? onClose;

  @override
  State<ThumbKissWindow> createState() => _ThumbKissWindowState();
}

class _ThumbKissWindowState extends State<ThumbKissWindow>
    with TickerProviderStateMixin {
  late final AnimationController _sparkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Per-frame glide for the partner's blob: network points arrive at ~4/s
  /// with jitter, so painting them raw teleports the blob. The displayed
  /// position chases the latest point with an exponential ease (~80ms time
  /// constant) — fast enough to feel live, smooth enough to read as one
  /// continuous motion.
  late final Ticker _smoother = createTicker(_onSmoothTick);
  Offset? _partnerDisplay;
  Duration _lastSmoothTick = Duration.zero;

  bool _wasMet = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  void _onSmoothTick(Duration elapsed) {
    final dt = _lastSmoothTick == Duration.zero
        ? 0.016
        : (elapsed - _lastSmoothTick).inMicroseconds / 1e6;
    _lastSmoothTick = elapsed;

    final viewModel = widget.viewModel;
    final target = viewModel.partnerVisible
        ? viewModel.partnerTouch?.offset
        : null;

    setState(() {
      if (target == null) {
        _partnerDisplay = null;
      } else if (_partnerDisplay == null ||
          (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        // First appearance snaps (no glide in from nowhere); reduced motion
        // always snaps.
        _partnerDisplay = target;
      } else {
        final k = 1 - math.exp(-dt * 12);
        _partnerDisplay = Offset.lerp(_partnerDisplay, target, k);
      }
    });

    if (target == null && _partnerDisplay == null) {
      _smoother.stop();
      _lastSmoothTick = Duration.zero;
    }
  }

  void _onViewModelChanged() {
    if (widget.viewModel.partnerVisible && !_smoother.isActive) {
      _lastSmoothTick = Duration.zero;
      _smoother.start();
    }
    final met = widget.viewModel.isMet;
    if (met && !_wasMet) {
      HapticFeedback.mediumImpact();
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _sparkle.value = 1;
      } else {
        _sparkle
          ..reset()
          ..repeat();
      }
    } else if (!met && _wasMet) {
      _sparkle.stop();
      _sparkle.value = 0;
    }
    _wasMet = met;
  }

  void _handlePointer(Offset localPosition, Size areaSize) {
    if (areaSize.width <= 0 || areaSize.height <= 0) return;
    final x = (localPosition.dx / areaSize.width).clamp(0.0, 1.0);
    final y = (localPosition.dy / areaSize.height).clamp(0.0, 1.0);
    widget.viewModel.onTouchMove(Offset(x, y));
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _smoother.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RetroWindow(
      title: AppStrings.thumbKissTitle,
      onClose: widget.onClose,
      width: 300,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.viewModel, _sparkle]),
        builder: (context, _) {
          final viewModel = widget.viewModel;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                viewModel.isMet
                    ? AppStrings.thumbKissMetMessage
                    : AppStrings.thumbKissHint,
                key: const Key('thumb-kiss-status-text'),
                textAlign: TextAlign.center,
                style: AppTextStyles.body2.copyWith(color: colors.ink),
              ),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 1,
                child: BevelBox(
                  style: BevelStyle.sunken,
                  color: colors.bg,
                  padding: const EdgeInsets.all(2),
                  child: Semantics(
                    label: AppStrings.thumbKissHint,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        // Raw pointer events, not GestureDetector pans: the
                        // pad lives inside scrollables, and on touch screens
                        // the scroll view steals the drag from the gesture
                        // arena moments after pointer-down — our pan gets
                        // CANCELED mid-press, which read as "blob disappears
                        // when I put my thumb down" on phones. Listener sits
                        // outside the arena entirely, so a press is a press.
                        // The inner GestureDetector claims vertical drags
                        // with no-op handlers purely so the parent scrollable
                        // doesn't scroll the page under a moving thumb.
                        return Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) =>
                              _handlePointer(e.localPosition, size),
                          onPointerMove: (e) =>
                              _handlePointer(e.localPosition, size),
                          onPointerUp: (_) => viewModel.onTouchEnd(),
                          onPointerCancel: (_) => viewModel.onTouchEnd(),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart: (_) {},
                            onVerticalDragUpdate: (_) {},
                            child: CustomPaint(
                              key: const Key('thumb-kiss-canvas'),
                              size: size,
                              painter: ThumbKissPainter(
                                myTouch: viewModel.myTouch,
                                // The smoothed display position, not the raw
                                // network point — see [_onSmoothTick].
                                partnerTouch: viewModel.partnerVisible
                                    ? (_partnerDisplay ??
                                          viewModel.partnerTouch?.offset)
                                    : null,
                                isMet: viewModel.isMet,
                                myColor: colors.accent,
                                partnerColor: colors.accent2,
                                flashColor: colors.warn,
                                sparklePhase: _sparkle.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.thumbKissLatencyHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(color: colors.chromeAlt),
              ),
            ],
          );
        },
      ),
    );
  }
}
