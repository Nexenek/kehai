import 'package:flutter/material.dart';

/// One line of text that drifts gently side to side **only when it doesn't
/// fit**, and holds still when it does.
///
/// This is the now-playing line on the little window — the one ambient
/// motion design-language.md allows per screen ("one orchestrated moment per
/// screen … no constant idle motion beyond the one ambient element"). It's a
/// slow ease-in-out drift rather than a hard wrap-around scroll, and under
/// reduced motion it degrades to a still, ellipsized line.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.pixelsPerSecond = 18,
  });

  final String text;
  final TextStyle style;

  /// Drift speed. Deliberately slow — this is peripheral vision material.
  final double pixelsPerSecond;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _textWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _textWidth(context);
        final overflow = width - constraints.maxWidth;

        if (still || overflow <= 0 || !constraints.maxWidth.isFinite) {
          _controller.stop();
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        final duration = Duration(
          milliseconds: (overflow / widget.pixelsPerSecond * 1000)
              .clamp(1200, 20000)
              .round(),
        );
        if (_controller.duration != duration || !_controller.isAnimating) {
          _controller
            ..duration = duration
            ..repeat(reverse: true);
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                -overflow * Curves.easeInOut.transform(_controller.value),
                0,
              ),
              child: child,
            ),
            child: SizedBox(
              width: width,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}
