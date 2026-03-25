import 'package:flutter/material.dart';

import '../core/palette.dart';

/// Retro pixel-styled text using the PressStart2P font.
///
/// All text rendered through this widget inherits the PICO-8 aesthetic.
/// Callers are responsible for choosing an appropriate [fontSize] for the
/// current screen size.
class PixelText extends StatelessWidget {
  const PixelText(
    this.text, {
    super.key,
    this.fontSize = 12,
    this.color = Pico8Palette.white,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final double fontSize;
  final Color color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        fontFamily: 'PressStart2P',
        fontSize: fontSize,
        color: color,
        height: 1.4,
      ),
    );
  }
}
