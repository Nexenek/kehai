import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/board_item.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/bevel_box.dart';
import '../../core/widgets/pixel_button.dart';
import '../../core/widgets/retro_window.dart';
import 'add_board_item_dialog.dart';
import 'board_drag_logic.dart';
import 'board_view_model.dart';

/// The shared board "window" — a fixed-aspect (4:3) corkboard-ish surface
/// both partners decorate together (kb/features.md "Shared board";
/// kb/design-language.md's desktop-metaphor "power-user wink: they
/// genuinely rearrange"). Self-contained, same as `InstantsWindow`/
/// `NotesWindow`: this batch builds the feature but does NOT wire it into
/// the home tray/layout — a caller just needs a [BoardViewModel] wired to
/// real repositories.
class BoardWindow extends StatelessWidget {
  const BoardWindow({super.key, required this.viewModel, this.onClose});

  final BoardViewModel viewModel;

  /// Makes the window's ♥ functional when it's shown inside the desktop
  /// companion drawer; decorative (null) in the other layouts.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return RetroWindow(
          title: AppStrings.boardTitle,
          onClose: onClose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BoardSurface(viewModel: viewModel),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: PixelButton(
                  primary: true,
                  icon: Icons.add,
                  label: AppStrings.boardAdd,
                  onPressed: () =>
                      showAddBoardItemMenu(context, viewModel: viewModel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The fixed-aspect corkboard surface: pixel-grid background, every item
/// positioned by its normalized x/y, drawn back-to-front by z.
class _BoardSurface extends StatefulWidget {
  const _BoardSurface({required this.viewModel});

  final BoardViewModel viewModel;

  @override
  State<_BoardSurface> createState() => _BoardSurfaceState();
}

class _BoardSurfaceState extends State<_BoardSurface> {
  // Ephemeral UI-only state — which item currently shows its ✕ delete
  // affordance. Never persisted, never touches the view model's items.
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showEmpty = widget.viewModel.items.isEmpty && !widget.viewModel.isLoading;
    final items = List<BoardItem>.of(widget.viewModel.items)
      ..sort((a, b) => a.z.compareTo(b.z));

    return LayoutBuilder(
      builder: (context, outer) {
        // A sensible width regardless of whether the surrounding layout
        // hands this a bounded width (the desktop companion drawer) or an
        // unbounded one (a bare test host) — mirrors
        // `InstantsWindow._InstantGrid`'s isFinite guard.
        final double width = outer.maxWidth.isFinite
            ? outer.maxWidth.clamp(240.0, 480.0).toDouble()
            : 360.0;

        return SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return SizedBox.expand(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.bg,
                      border: Border.all(color: colors.ink, width: 2),
                    ),
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _BoardGridPainter(
                                line: colors.chromeAlt.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          if (showEmpty)
                            Positioned.fill(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    AppStrings.boardEmpty,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.body2.copyWith(
                                      color: colors.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final item in items)
                            _BoardItemView(
                              key: ValueKey(item.id),
                              item: item,
                              boardSize: boardSize,
                              selected: _selectedId == item.id,
                              onSelect: () => setState(
                                () => _selectedId =
                                    _selectedId == item.id ? null : item.id,
                              ),
                              onDelete: () {
                                setState(() => _selectedId = null);
                                widget.viewModel.deleteItem(item.id);
                              },
                              onDragPhase: (phase, delta) =>
                                  widget.viewModel.handleDrag(
                                    id: item.id,
                                    phase: phase,
                                    pixelDelta: delta,
                                    boardSize: boardSize,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Subtle pixel grid over the board's bg tint (design-language.md: "subtle
/// pixel-grid" corkboard backing) — a light dot/line lattice, not a full
/// scanline shader (that's reserved for standby screens per the design
/// language, not an interactive one).
class _BoardGridPainter extends CustomPainter {
  const _BoardGridPainter({required this.line});

  final Color line;

  static const _cell = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardGridPainter oldDelegate) =>
      oldDelegate.line != line;
}

/// One draggable, selectable board item — a note square, a framed photo, or
/// a bare sticker glyph, tilted by [BoardItem.rot] and centered on its
/// normalized position.
class _BoardItemView extends StatelessWidget {
  const _BoardItemView({
    super.key,
    required this.item,
    required this.boardSize,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
    required this.onDragPhase,
  });

  final BoardItem item;
  final Size boardSize;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final void Function(BoardDragPhase phase, Offset delta) onDragPhase;

  static const _noteSize = 92.0;
  static const _photoSize = 92.0;
  static const _stickerSize = 64.0;

  double get _size => switch (item.type) {
    BoardItemType.note => _noteSize,
    BoardItemType.photo => _photoSize,
    BoardItemType.sticker => _stickerSize,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = _size;
    final left = item.x * boardSize.width - size / 2;
    final top = item.y * boardSize.height - size / 2;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onSelect,
        onLongPress: onSelect,
        onPanStart: (_) => onDragPhase(BoardDragPhase.start, Offset.zero),
        onPanUpdate: (details) =>
            onDragPhase(BoardDragPhase.update, details.delta),
        onPanEnd: (_) => onDragPhase(BoardDragPhase.end, Offset.zero),
        onPanCancel: () => onDragPhase(BoardDragPhase.cancel, Offset.zero),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Semantics(
            button: true,
            selected: selected,
            label: _semanticLabel,
            child: Transform.rotate(
              angle: item.rot * math.pi / 180,
              child: SizedBox(
                width: size + 16,
                height: size + 16,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    _BoardItemContent(
                      item: item,
                      size: size,
                      selected: selected,
                    ),
                    if (selected)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Semantics(
                              button: true,
                              label: AppStrings.boardDeleteItemTooltip,
                              child: BevelBox(
                                color: colors.warn,
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  Icons.close,
                                  size: 12,
                                  color: colors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticLabel => switch (item.type) {
    BoardItemType.note => item.text,
    BoardItemType.photo => AppStrings.boardAddPhoto,
    BoardItemType.sticker => item.sticker,
  };
}

class _BoardItemContent extends StatelessWidget {
  const _BoardItemContent({
    required this.item,
    required this.size,
    required this.selected,
  });

  final BoardItem item;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedBorder = selected
        ? Border.all(color: colors.accent, width: 3)
        : Border.all(color: colors.ink, width: 1);

    switch (item.type) {
      case BoardItemType.note:
        return Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: item.color.colorOf(colors),
            border: selectedBorder,
          ),
          child: Text(
            item.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(color: colors.ink),
          ),
        );
      case BoardItemType.photo:
        return Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: colors.surface, border: selectedBorder),
          child: item.imageUrl == null
              ? ColoredBox(color: colors.chromeAlt)
              : Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stack) =>
                      ColoredBox(color: colors.chromeAlt),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return ColoredBox(color: colors.chromeAlt);
                  },
                ),
        );
      case BoardItemType.sticker:
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: selected
              ? BoxDecoration(border: Border.all(color: colors.accent, width: 2))
              : null,
          child: Text(
            item.sticker,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.kaomojiMedium.copyWith(color: colors.ink),
          ),
        );
    }
  }
}
