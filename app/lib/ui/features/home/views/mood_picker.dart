import 'package:flutter/material.dart';

import '../../../../domain/models/mood.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_focus_border.dart';

/// A grid of kaomoji mood tiles. Each tile is icon(kaomoji)+text — never
/// color alone — per the accessibility floor.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, required this.selectedId, required this.onSelect});

  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: MoodCatalog.all.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, index) {
        final mood = MoodCatalog.all[index];
        final selected = mood.id == selectedId;
        return _MoodTile(
          mood: mood,
          selected: selected,
          onTap: () => onSelect(mood.id),
        );
      },
    );
  }
}

class _MoodTile extends StatefulWidget {
  const _MoodTile({required this.mood, required this.selected, required this.onTap});

  final Mood mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MoodTile> createState() => _MoodTileState();
}

class _MoodTileState extends State<_MoodTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tileColor = widget.mood.colorOf(colors);

    return PixelFocusBorder(
      focused: _focused,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: GestureDetector(
          onTap: widget.onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Semantics(
              button: true,
              selected: widget.selected,
              label: widget.mood.label,
              child: BevelBox(
                color: widget.selected ? tileColor : colors.surface,
                style: widget.selected ? BevelStyle.sunken : BevelStyle.raised,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Text(widget.mood.kaomoji, style: AppTextStyles.caption.copyWith(color: colors.ink)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.mood.label,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.ink,
                          fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
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
}
