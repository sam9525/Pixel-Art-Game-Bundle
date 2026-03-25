import 'package:flutter/material.dart';

import '../core/palette.dart';

/// Heads-up display overlay for Flame games.
///
/// Shows the current [score] on the left (with animated transitions),
/// [lives] as heart icons in the center, and a pause button on the right.
/// Designed to be registered as a Flame overlay widget builder.
///
/// Remains a [StatelessWidget] — reactivity is handled by
/// [ListenableBuilder] in the parent.
class PixelHud extends StatelessWidget {
  const PixelHud({
    super.key,
    required this.score,
    required this.lives,
    required this.onPause,
  });

  final int score;
  final int lives;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final fontSize = (screenWidth * 0.025).clamp(8.0, 16.0);
    final iconSize = (screenWidth * 0.04).clamp(14.0, 28.0);

    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: fontSize,
          vertical: fontSize * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Color.fromRGBO(95, 87, 79, 0.85), // darkGrey at 0.85 opacity
          border: Border(
            bottom: BorderSide(
              color: Pico8Palette.darkBlue,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // ---- Score (left) with animated transition ----
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Text(
                  'SCR ${score.toString().padLeft(6, '0')}',
                  key: ValueKey<int>(score),
                  style: TextStyle(
                    fontFamily: 'PressStart2P',
                    fontSize: fontSize,
                    color: Pico8Palette.yellow,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // ---- Lives (center) with animated transition ----
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  lives.clamp(0, 9),
                  (index) => Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: fontSize * 0.15),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                            scale: animation, child: child);
                      },
                      child: Icon(
                        Icons.favorite,
                        key: ValueKey<int>(lives * 10 + index),
                        color: Pico8Palette.red,
                        size: iconSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ---- Pause button (right) ----
            GestureDetector(
              onTap: onPause,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(fontSize * 0.3),
                child: Icon(
                  Icons.pause,
                  color: Pico8Palette.white,
                  size: iconSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
