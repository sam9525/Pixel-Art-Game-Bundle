import 'package:flutter/material.dart';

import '../core/palette.dart';

/// A virtual arcade button styled with PICO-8 palette colors.
///
/// Uses [GestureDetector] to report press and release events so callers can
/// implement continuous-hold input (e.g. "move left while held").
///
/// [onTapDown] fires when the finger touches the button.
/// [onTapUp] fires when the finger lifts or the gesture is cancelled.
class ArcadeButton extends StatelessWidget {
  const ArcadeButton({
    super.key,
    required this.icon,
    required this.onTapDown,
    required this.onTapUp,
    this.size = 64,
  });

  final IconData icon;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapUp,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Pico8Palette.darkGrey,
          border: Border.all(
            color: Pico8Palette.lightGrey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Pico8Palette.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}
