import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/art_scene.dart';

/// Paints a composited paper-doll scene: the resolved layers stacked in
/// paint order inside one fixed square canvas.
///
/// Every layer is drawn edge-to-edge over the same square, which is exactly
/// what ADR-13's "fixed canvas + anchor grid" buys us — the artist draws
/// each piece in place on one canvas, and alignment is then free: no
/// offsets, no anchors to configure, nothing to drift when a layer is
/// swapped.
///
/// [FilterQuality.none] everywhere: nearest-neighbour scaling is what keeps
/// pixel art crisp (design-language.md — "texture filtering OFF ... or the
/// crispness dies").
class ArtSceneView extends StatelessWidget {
  const ArtSceneView({super.key, required this.scene, this.size});

  /// Already resolved by [resolveArtScene] — this widget does no matching
  /// of its own, it just draws what it's handed, bottom layer first.
  final List<ArtLayer> scene;

  /// Fixed side length. Null means "as big a square as the parent allows",
  /// which is what the mini window's portrait slot wants.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final canvas = Stack(
      fit: StackFit.expand,
      children: [
        for (final layer in scene)
          Image.network(
            layer.imageUrl,
            key: ValueKey(layer.id),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            // Keeps the previous frame on screen while a swapped layer
            // loads, so a mood change doesn't flash an empty canvas.
            gaplessPlayback: true,
            // A layer that fails to load is simply absent — the rest of the
            // scene still reads, and the portrait never shows a broken-image
            // glyph in the middle of the partner window.
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
      ],
    );

    final fixed = size;
    if (fixed != null) {
      return SizedBox(width: fixed, height: fixed, child: canvas);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // The biggest square that fits. Guard against an unbounded axis
        // (a Column/Row that hasn't been given a size yet) by falling back
        // to whichever side IS bounded.
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final side = switch ((width.isFinite, height.isFinite)) {
          (true, true) => math.min(width, height),
          (true, false) => width,
          (false, true) => height,
          _ => 96.0,
        };
        return Center(
          child: SizedBox(width: side, height: side, child: canvas),
        );
      },
    );
  }
}
