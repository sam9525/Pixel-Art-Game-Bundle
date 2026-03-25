import 'package:flutter/material.dart';

import '../core/palette.dart';

/// Full-screen "GAME OVER" overlay for Flame games.
///
/// Displays the final [score] and [highScore] with animated effects,
/// plus Restart and Quit actions. Features flashing title text, score
/// count-up animation, CRT scanlines, and decorative pixel borders.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.score,
    required this.highScore,
    required this.onRestart,
    required this.onQuit,
  });

  final int score;
  final int highScore;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _flashController;
  late final AnimationController _countUpController;
  late final Animation<int> _countUpAnimation;

  @override
  void initState() {
    super.initState();

    // Flashing title + "NEW HIGH SCORE!" blink — repeats forever.
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Score count-up from 0 → final score over ~1 second.
    _countUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _countUpAnimation = IntTween(
      begin: 0,
      end: widget.score,
    ).animate(CurvedAnimation(
      parent: _countUpController,
      curve: Curves.easeOut,
    ));
    _countUpController.forward();
  }

  @override
  void dispose() {
    _flashController.dispose();
    _countUpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNewHighScore = widget.score > widget.highScore;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final titleSize = (shortSide * 0.06).clamp(14.0, 32.0);
        final bodySize = (shortSide * 0.03).clamp(8.0, 16.0);
        final smallSize = (shortSide * 0.022).clamp(6.0, 12.0);
        final buttonPadH = (shortSide * 0.05).clamp(12.0, 32.0);
        final buttonPadV = (shortSide * 0.02).clamp(8.0, 16.0);
        final spacing = (shortSide * 0.03).clamp(8.0, 24.0);

        return Container(
          color: Pico8Palette.black.withValues(alpha: 0.85),
          child: Center(
            child: Container(
              constraints:
                  BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
              child: _PixelBorderBox(
                child: Stack(
                  children: [
                    // Main content
                    Padding(
                      padding: EdgeInsets.all(spacing * 1.5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flashing "GAME OVER" title
                          AnimatedBuilder(
                            animation: _flashController,
                            builder: (context, child) {
                              final color = Color.lerp(
                                Pico8Palette.red,
                                Pico8Palette.darkPurple,
                                _flashController.value,
                              )!;
                              return Text(
                                'GAME OVER',
                                style: TextStyle(
                                  fontFamily: 'PressStart2P',
                                  fontSize: titleSize,
                                  color: color,
                                ),
                              );
                            },
                          ),
                          SizedBox(height: spacing * 1.5),

                          // Score count-up
                          AnimatedBuilder(
                            animation: _countUpAnimation,
                            builder: (context, child) {
                              return Text(
                                'SCORE  ${_countUpAnimation.value.toString().padLeft(6, '0')}',
                                style: TextStyle(
                                  fontFamily: 'PressStart2P',
                                  fontSize: bodySize,
                                  color: Pico8Palette.yellow,
                                ),
                              );
                            },
                          ),
                          SizedBox(height: spacing * 0.6),

                          // High score
                          Text(
                            'BEST   ${widget.highScore.toString().padLeft(6, '0')}',
                            style: TextStyle(
                              fontFamily: 'PressStart2P',
                              fontSize: bodySize,
                              color: Pico8Palette.orange,
                            ),
                          ),

                          // New high score indicator
                          if (isNewHighScore) ...[
                            SizedBox(height: spacing),
                            AnimatedBuilder(
                              animation: _flashController,
                              builder: (context, child) {
                                return Opacity(
                                  opacity:
                                      _flashController.value > 0.5 ? 1.0 : 0.0,
                                  child: Text(
                                    'NEW HIGH SCORE!',
                                    style: TextStyle(
                                      fontFamily: 'PressStart2P',
                                      fontSize: smallSize,
                                      color: Pico8Palette.yellow,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],

                          SizedBox(height: spacing * 2),

                          // Buttons
                          _PixelButton(
                            label: 'RESTART',
                            color: Pico8Palette.green,
                            fontSize: bodySize,
                            paddingH: buttonPadH,
                            paddingV: buttonPadV,
                            onTap: widget.onRestart,
                          ),
                          SizedBox(height: spacing),
                          _PixelButton(
                            label: 'QUIT',
                            color: Pico8Palette.lightGrey,
                            fontSize: bodySize,
                            paddingH: buttonPadH,
                            paddingV: buttonPadV,
                            onTap: widget.onQuit,
                          ),
                        ],
                      ),
                    ),

                    // CRT scanline overlay
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CrtScanlinePainter(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Decorative pixel border built from small squares in a checkerboard pattern.
class _PixelBorderBox extends StatelessWidget {
  const _PixelBorderBox({required this.child});

  final Widget child;

  static const double _pixelSize = 4.0;
  static const List<Color> _borderColors = [
    Pico8Palette.lavender,
    Pico8Palette.darkPurple,
  ];

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _PixelBorderPainter(
        pixelSize: _pixelSize,
        colors: _borderColors,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_pixelSize * 2),
        child: Container(
          decoration: const BoxDecoration(
            color: Pico8Palette.darkBlue,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paints a decorative checkerboard pixel border around the widget.
class _PixelBorderPainter extends CustomPainter {
  _PixelBorderPainter({
    required this.pixelSize,
    required this.colors,
  });

  final double pixelSize;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final borderThickness = pixelSize * 2;

    for (double x = 0; x < size.width; x += pixelSize) {
      for (double y = 0; y < size.height; y += pixelSize) {
        // Only draw in the border region
        final inBorder = y < borderThickness ||
            y >= size.height - borderThickness ||
            x < borderThickness ||
            x >= size.width - borderThickness;
        if (!inBorder) continue;

        final ix = (x / pixelSize).floor();
        final iy = (y / pixelSize).floor();
        final colorIndex = (ix + iy) % colors.length;

        final paint = Paint()..color = colors[colorIndex];
        canvas.drawRect(
          Rect.fromLTWH(x, y, pixelSize, pixelSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBorderPainter oldDelegate) =>
      oldDelegate.pixelSize != pixelSize;
}

/// Paints semi-transparent horizontal scanlines for a CRT monitor effect.
class _CrtScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Pico8Palette.black.withValues(alpha: 0.08);
    const lineHeight = 2.0;
    const gap = 2.0;

    for (double y = 0; y < size.height; y += lineHeight + gap) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, lineHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Internal retro-styled button shared between overlay screens.
class _PixelButton extends StatelessWidget {
  const _PixelButton({
    required this.label,
    required this.color,
    required this.fontSize,
    required this.paddingH,
    required this.paddingV,
    required this.onTap,
  });

  final String label;
  final Color color;
  final double fontSize;
  final double paddingH;
  final double paddingV;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: paddingH,
          vertical: paddingV,
        ),
        decoration: BoxDecoration(
          color: Pico8Palette.darkGrey,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: fontSize,
            color: color,
          ),
        ),
      ),
    );
  }
}
