import 'package:flutter/material.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _sparkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _wasMet = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
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
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (d) =>
                              _handlePointer(d.localPosition, size),
                          onPanUpdate: (d) =>
                              _handlePointer(d.localPosition, size),
                          onPanEnd: (_) => viewModel.onTouchEnd(),
                          onPanCancel: viewModel.onTouchEnd,
                          child: CustomPaint(
                            key: const Key('thumb-kiss-canvas'),
                            size: size,
                            painter: ThumbKissPainter(
                              myTouch: viewModel.myTouch,
                              partnerTouch: viewModel.partnerVisible
                                  ? viewModel.partnerTouch?.offset
                                  : null,
                              isMet: viewModel.isMet,
                              myColor: colors.accent,
                              partnerColor: colors.accent2,
                              flashColor: colors.warn,
                              sparklePhase: _sparkle.value,
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
