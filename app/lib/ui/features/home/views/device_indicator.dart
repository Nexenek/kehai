import 'package:flutter/material.dart';

import '../../../core/strings/app_strings.dart';
import '../../../core/widgets/device_glyph.dart';

/// The pair of phone/desktop glyphs from design-language.md's signature
/// element: "tiny pixel phone/monitor glyphs — lit = that device online
/// now, both lit = both".
class DeviceIndicator extends StatelessWidget {
  const DeviceIndicator({
    super.key,
    required this.phoneOnline,
    required this.desktopOnline,
  });

  final bool phoneOnline;
  final bool desktopOnline;

  String get _combinedTooltip {
    if (phoneOnline && desktopOnline) return AppStrings.onBothTooltip;
    if (phoneOnline) return AppStrings.onPhoneTooltip;
    if (desktopOnline) return AppStrings.onDesktopTooltip;
    return AppStrings.offlineTooltip;
  }

  @override
  Widget build(BuildContext context) {
    // Both glyphs share one combined tooltip message (phone / computer /
    // both / offline) rather than describing themselves individually.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DeviceGlyph(
          kind: DeviceGlyphKind.phone,
          lit: phoneOnline,
          tooltip: _combinedTooltip,
        ),
        const SizedBox(width: 6),
        DeviceGlyph(
          kind: DeviceGlyphKind.desktop,
          lit: desktopOnline,
          tooltip: _combinedTooltip,
        ),
      ],
    );
  }
}
