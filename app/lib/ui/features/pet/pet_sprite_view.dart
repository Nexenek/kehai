import 'package:flutter/material.dart';

import '../../../domain/models/pet.dart';
import '../../core/theme/app_colors.dart';
import 'pet_painter.dart';
import 'pet_state.dart';

/// The pet itself: a painted 16×16 sprite with a two-frame idle "breathe"
/// (frame two sits one cell lower — a slow, tiny bob).
///
/// This is the one ambient motion in the window (design-language.md: "one
/// orchestrated moment per screen … no constant idle motion beyond the one
/// ambient element"). Asleep it breathes slower; under the OS reduced-motion
/// setting it holds perfectly still on frame one.
class PetSpriteView extends StatefulWidget {
  const PetSpriteView({
    super.key,
    required this.variant,
    required this.outfit,
    required this.state,
    this.size = 128,
  });

  final PetVariant variant;
  final PetOutfit outfit;
  final PetState state;
  final double size;

  /// Awake breathe period; each frame holds half of it.
  static const awakePeriod = Duration(milliseconds: 1800);

  /// Slower while napping.
  static const sleepyPeriod = Duration(milliseconds: 3000);

  @override
  State<PetSpriteView> createState() => _PetSpriteViewState();
}

class _PetSpriteViewState extends State<PetSpriteView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PetSpriteView.awakePeriod,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncController({required bool still}) {
    final period = widget.state.sleepy
        ? PetSpriteView.sleepyPeriod
        : PetSpriteView.awakePeriod;
    if (still) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      return;
    }
    if (_controller.duration != period || !_controller.isAnimating) {
      _controller
        ..duration = period
        ..repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.disableAnimationsOf(context);
    _syncController(still: still);

    // Both frames are built once per state change, not per tick — the
    // animation only picks which prebuilt grid to hand the painter.
    final frames = [
      for (var bob = 0; bob < 2; bob++)
        buildPetCells(
          variant: widget.variant,
          outfit: widget.outfit,
          expression: widget.state.expression,
          blushing: widget.state.blushing,
          colors: colors,
          bob: bob,
        ),
    ];

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final frame = (!still && _controller.value >= 0.5) ? 1 : 0;
          return CustomPaint(
            painter: PetPainter(frames[frame]),
            size: Size.square(widget.size),
          );
        },
      ),
    );
  }
}
