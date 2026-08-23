import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/settings/view_models/phone_superpowers_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-function coverage for the Android superpowers screen's
/// `shareFocusedApp` window preview (kb/features.md "Focused-app status").
/// Mirrors `sharing_settings_preview_test.dart` on desktop, plus the one
/// extra Android-only input: the Usage Access OS grant, which gates the
/// raw signal itself (not just our own opt-in).
void main() {
  group('PhoneSuperpowersViewModel.resolvePreviewMessage', () {
    test('sharing off always wins', () {
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: false,
          hasUsageAccess: true,
          hasReading: true,
          mappedLabel: 'gaming',
        ),
        AppStrings.sharingPreviewOff,
      );
    });

    test('on + no usage access asks for the grant first', () {
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasUsageAccess: false,
          hasReading: false,
          mappedLabel: null,
        ),
        AppStrings.sharingPreviewGrantUsageAccess,
      );
    });

    test('on + usage access + mapped package names the label', () {
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasUsageAccess: true,
          hasReading: true,
          mappedLabel: 'gaming',
        ),
        AppStrings.sharingPreviewSharing('gaming'),
      );
    });

    test('on + usage access + unmapped package shares nothing', () {
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasUsageAccess: true,
          hasReading: true,
          mappedLabel: null,
        ),
        AppStrings.sharingPreviewUnmapped,
      );
    });

    test('on + usage access + nothing recent to report', () {
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasUsageAccess: true,
          hasReading: false,
          mappedLabel: null,
        ),
        AppStrings.sharingPreviewNoReadingAndroid,
      );
    });

    test('usage access is checked before "no reading"', () {
      // With both false, the more actionable message ("go grant usage
      // access") should win over the generic "nothing recent" one.
      expect(
        PhoneSuperpowersViewModel.resolvePreviewMessage(
          shareFocusedApp: true,
          hasUsageAccess: false,
          hasReading: false,
          mappedLabel: null,
        ),
        AppStrings.sharingPreviewGrantUsageAccess,
      );
    });
  });
}
