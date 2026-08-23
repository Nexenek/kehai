import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/settings/view_models/sharing_settings_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-function coverage for the desktop sharing-settings dialog's "what
/// we'd share right now" preview (kb/features.md "Focused-app status"):
/// given toggle state + probe result, what line should show. No platform
/// channel, no timer, no I/O — [SharingSettingsViewModel.resolvePreviewMessage]
/// is a plain function of its three inputs.
void main() {
  group('SharingSettingsViewModel.resolvePreviewMessage', () {
    test('sharing off always wins, regardless of the probe', () {
      expect(
        SharingSettingsViewModel.resolvePreviewMessage(
          shareFocusedApp: false,
          hasReading: true,
          mappedLabel: 'coding ⌨︎',
        ),
        AppStrings.sharingPreviewOff,
      );
      expect(
        SharingSettingsViewModel.resolvePreviewMessage(
          shareFocusedApp: false,
          hasReading: false,
          mappedLabel: null,
        ),
        AppStrings.sharingPreviewOff,
      );
    });

    test('on + mapped app names the label', () {
      expect(
        SharingSettingsViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasReading: true,
          mappedLabel: 'coding ⌨︎',
        ),
        AppStrings.sharingPreviewSharing('coding ⌨︎'),
      );
    });

    test(
      'on + unmapped app (shareUnknownApps off) says nothing is shared',
      () {
        expect(
          SharingSettingsViewModel.resolvePreviewMessage(
            shareFocusedApp: true,
            hasReading: true,
            mappedLabel: null,
          ),
          AppStrings.sharingPreviewUnmapped,
        );
      },
    );

    test(
      'on + no reading available (e.g. GNOME Wayland) says so honestly',
      () {
        expect(
          SharingSettingsViewModel.resolvePreviewMessage(
            shareFocusedApp: true,
            hasReading: false,
            mappedLabel: null,
          ),
          AppStrings.sharingPreviewNoReading,
        );
      },
    );

    test('no-reading takes priority over an (impossible) mapped label', () {
      // Defensive: a caller should never pass hasReading:false with a
      // non-null label, but if it does, "no reading" still wins — there's
      // nothing to safely show.
      expect(
        SharingSettingsViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasReading: false,
          mappedLabel: 'coding ⌨︎',
        ),
        AppStrings.sharingPreviewNoReading,
      );
    });
  });
}
