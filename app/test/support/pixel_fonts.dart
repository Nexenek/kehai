import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's real pixel fonts into the test binding.
///
/// Widget tests otherwise measure text with a stand-in font whose glyphs are
/// all one em wide — roughly 2.5× VT323 — which makes every kaomoji look like
/// an overflow. Any test that asserts something *fits* has to use the fonts
/// the app actually ships.
Future<void> loadPixelFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fonts = <String, String>{
    'VT323': 'assets/fonts/VT323-Regular.ttf',
    'PixelifySans': 'assets/fonts/PixelifySans-Regular.ttf',
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}
