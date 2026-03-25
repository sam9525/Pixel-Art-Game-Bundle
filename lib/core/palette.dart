import 'dart:ui' show Color;

/// PICO-8 16-color palette.
///
/// All colors in the codebase MUST be pulled from this class.
/// No raw hex values anywhere else.
class Pico8Palette {
  Pico8Palette._();

  static const Color black = Color(0xFF000000);
  static const Color darkBlue = Color(0xFF1D2B53);
  static const Color darkPurple = Color(0xFF7E2553);
  static const Color darkGreen = Color(0xFF008751);
  static const Color brown = Color(0xFFAB5236);
  static const Color darkGrey = Color(0xFF5F574F);
  static const Color lightGrey = Color(0xFFC2C3C7);
  static const Color white = Color(0xFFFFF1E8);
  static const Color red = Color(0xFFFF004D);
  static const Color orange = Color(0xFFFFA300);
  static const Color yellow = Color(0xFFFFEC27);
  static const Color green = Color(0xFF00E436);
  static const Color blue = Color(0xFF29ADFF);
  static const Color lavender = Color(0xFF83769C);
  static const Color pink = Color(0xFFFF77A8);
  static const Color lightPeach = Color(0xFFFFCCAA);

  /// All 16 colors as a list, indexed 0-15.
  static const List<Color> all = [
    black, darkBlue, darkPurple, darkGreen,
    brown, darkGrey, lightGrey, white,
    red, orange, yellow, green,
    blue, lavender, pink, lightPeach,
  ];
}
