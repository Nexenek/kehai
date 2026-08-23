import 'package:flutter/material.dart';

/// Pixel-font type scale. Sizes are chosen at whole multiples so the pixel
/// fonts render crisply without fractional scaling (design-language.md:
/// "pixel fonts render at integer scale factors ... never fractional
/// sizes, never anti-aliased").
///
/// `PixelifySans` = display/chrome (title bars, buttons, headings) — stand-in
/// for Public Pixel until it can be downloaded (see pubspec.yaml TODO).
/// `VT323` = body/dense text — stand-in for LanaPixel.
class AppTextStyles {
  const AppTextStyles._();

  static const String display = 'PixelifySans';
  static const String body = 'VT323';

  static const TextStyle titleBar = TextStyle(
    fontFamily: display,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle heading = TextStyle(
    fontFamily: display,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle button = TextStyle(
    fontFamily: display,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body1 = TextStyle(
    fontFamily: body,
    fontSize: 20,
    height: 1.25,
  );

  static const TextStyle body2 = TextStyle(
    fontFamily: body,
    fontSize: 17,
    height: 1.25,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: body,
    fontSize: 15,
    height: 1.2,
  );

  static const TextStyle kaomojiLarge = TextStyle(
    fontFamily: body,
    fontSize: 40,
    height: 1.1,
  );

  static const TextStyle kaomojiMedium = TextStyle(
    fontFamily: body,
    fontSize: 26,
    height: 1.1,
  );
}
