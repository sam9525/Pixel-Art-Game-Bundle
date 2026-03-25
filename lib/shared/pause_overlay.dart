import 'package:flutter/material.dart';

import '../core/palette.dart';

/// Full-screen "PAUSED" overlay for Flame games.
///
/// Features a slow-pulsing title, CRT scanline effect, and decorative
/// pixel border. Provides Resume and Quit actions.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.onQuit,
  });

  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final titleSize = (shortSide * 0.06).clamp(14.0, 32.0);
        final bodySize = (shortSide * 0.03).clamp(8.0, 16.0);
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
                          // Pulsing "PAUSED" title
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Text(
                              'PAUSED',
                              style: TextStyle(
                                fontFamily: 'PressStart2P',
                                fontSize: titleSize,
                                color: Pico8Palette.blue,
                              ),
                            ),
                          ),
                          SizedBox(height: spacing * 2),

                          // Buttons
                          _PauseButton(
                            label: 'RESUME',
                            color: Pico8Palette.green,
                            fontSize: bodySize,
                            paddingH: buttonPadH,
                            paddingV: buttonPadV,
                            onTap: widget.onResume,
                          ),
                          SizedBox(height: spacing),
                          _PauseButton(
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

/// Internal retro-styled button for the pause overlay.
class _PauseButton extends StatelessWidget {
  const _PauseButton({
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
