import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';

/// Cinematic "arcade power-on" start overlay.
///
/// Displays a staggered title-sequence entrance with floating pixel particles,
/// CRT effects, and a satisfying tap-flash when the player starts.
class StartOverlay extends StatefulWidget {
  const StartOverlay({
    super.key,
    required this.title,
    required this.icon,
    required this.highScore,
    required this.accentColor,
    required this.onStart,
    required this.onQuit,
  });

  final String title;
  final String icon;
  final int highScore;
  final Color accentColor;
  final VoidCallback onStart;
  final VoidCallback onQuit;

  @override
  State<StartOverlay> createState() => _StartOverlayState();
}

class _StartOverlayState extends State<StartOverlay>
    with TickerProviderStateMixin {
  // C1: Staggered entrance (one-shot)
  late final AnimationController _entranceController;
  // C2: "PRESS START" blink
  late final AnimationController _flashController;
  // C3: Title glow breathing
  late final AnimationController _glowController;
  // C4: Background particles
  late final AnimationController _particleController;
  // C5: Tap feedback flash
  late final AnimationController _tapFeedbackController;

  bool _tapped = false;
  late final FocusNode _focusNode;

  // Pre-computed entrance sub-animations
  late final Animation<double> _bgFade;
  late final Animation<double> _iconFade;
  late final Animation<double> _dividerFade;
  late final Animation<double> _scoreFade;
  late final Animation<double> _promptFade;
  late final Animation<double> _backFade;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    // C1: Entrance sequence
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _bgFade = _stagger(0.0, 0.25);
    _iconFade = _stagger(0.15, 0.35);
    _dividerFade = _stagger(0.45, 0.60);
    _scoreFade = _stagger(0.55, 0.70);
    _promptFade = _stagger(0.65, 0.85);
    _backFade = _stagger(0.75, 1.0);

    // C2: Flash (starts after entrance)
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // C3: Title glow (starts immediately)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // C4: Particles (starts immediately)
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    // C5: Tap feedback
    _tapFeedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _tapFeedbackController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onStart();
      }
    });

    // Start entrance, then begin flash loop
    _entranceController.forward();
    _entranceController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _flashController.repeat(reverse: true);
      }
    });
  }

  CurvedAnimation _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _tapFeedbackController.dispose();
    _particleController.dispose();
    _glowController.dispose();
    _flashController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _handleStart() {
    if (_tapped) return;
    _tapped = true;
    _tapFeedbackController.forward(from: 0.0);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _handleStart();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onQuit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: _handleStart,
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortSide = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            final titleSize = (shortSide * 0.055).clamp(12.0, 28.0);
            final bodySize = (shortSide * 0.03).clamp(8.0, 16.0);
            final smallSize = (shortSide * 0.022).clamp(6.0, 12.0);
            final iconSize = (shortSide * 0.15).clamp(40.0, 80.0);
            final spacing = (shortSide * 0.03).clamp(8.0, 24.0);
            final buttonPadH = (shortSide * 0.05).clamp(12.0, 32.0);
            final buttonPadV = (shortSide * 0.02).clamp(8.0, 16.0);

            final titleLetters = widget.title.toUpperCase().characters.toList();

            return AnimatedBuilder(
              animation: _tapFeedbackController,
              builder: (context, child) {
                // Tap flash: scale bounce
                final tapVal = _tapFeedbackController.value;
                final tapScale = tapVal < 0.4
                    ? 1.0 + 0.05 * (tapVal / 0.4)
                    : 1.05 - 0.05 * ((tapVal - 0.4) / 0.6);

                return Stack(
                  children: [
                    // Layer 0: Background fade
                    FadeTransition(
                      opacity: _bgFade,
                      child: Container(
                        color: Pico8Palette.black.withValues(alpha: 0.95),
                      ),
                    ),

                    // Layer 1: Floating pixel particles
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PixelParticlePainter(
                          animation: _particleController,
                          accentColor: widget.accentColor,
                        ),
                      ),
                    ),

                    // Layer 2: CRT scanlines (full screen)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: const _CrtScanlinePainter(),
                        ),
                      ),
                    ),

                    // Layer 3: Main content
                    Positioned.fill(
                      child: Transform.scale(
                        scale: tapScale,
                        child: Align(
                          alignment: const Alignment(0, -0.1),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.85,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Icon
                                FadeTransition(
                                  opacity: _iconFade,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.3),
                                      end: Offset.zero,
                                    ).animate(_iconFade),
                                    child: Text(
                                      widget.icon,
                                      style: TextStyle(fontSize: iconSize),
                                    ),
                                  ),
                                ),
                                SizedBox(height: spacing * 0.6),

                                // Title: letter-by-letter stagger
                                AnimatedBuilder(
                                  animation: _entranceController,
                                  builder: (context, _) {
                                    return AnimatedBuilder(
                                      animation: _glowController,
                                      builder: (context, _) {
                                        final glowBlur = 12.0 +
                                            12.0 * _glowController.value;
                                        final glowAlpha = 0.4 +
                                            0.3 * _glowController.value;
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (int i = 0;
                                                i < titleLetters.length;
                                                i++)
                                              _buildTitleLetter(
                                                titleLetters[i],
                                                i,
                                                titleLetters.length,
                                                titleSize,
                                                glowBlur,
                                                glowAlpha,
                                              ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                                SizedBox(height: spacing * 0.6),

                                // Divider
                                FadeTransition(
                                  opacity: _dividerFade,
                                  child: _PixelDivider(
                                    color: widget.accentColor,
                                  ),
                                ),
                                SizedBox(height: spacing),

                                // High score
                                if (widget.highScore > 0) ...[
                                  FadeTransition(
                                    opacity: _scoreFade,
                                    child: Text(
                                      'HI-SCORE  ${widget.highScore.toString().padLeft(6, '0')}',
                                      style: TextStyle(
                                        fontFamily: 'PressStart2P',
                                        fontSize: smallSize,
                                        color: Pico8Palette.orange,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: spacing),
                                ],

                                SizedBox(height: spacing * 0.5),

                                // "PRESS START" button
                                FadeTransition(
                                  opacity: _promptFade,
                                  child: AnimatedBuilder(
                                    animation: _flashController,
                                    builder: (context, child) {
                                      final flashVal =
                                          _flashController.value;
                                      final opacity = 0.4 + 0.6 * flashVal;
                                      final shadowBlur =
                                          4.0 + 8.0 * flashVal;
                                      return Opacity(
                                        opacity: opacity,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: buttonPadH,
                                            vertical: buttonPadV,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Pico8Palette.darkGrey
                                                .withValues(alpha: 0.5),
                                            border: Border.all(
                                              color: Pico8Palette.yellow,
                                              width: 2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'PRESS START',
                                            style: TextStyle(
                                              fontFamily: 'PressStart2P',
                                              fontSize: bodySize,
                                              color: Pico8Palette.yellow,
                                              shadows: [
                                                Shadow(
                                                  color: Pico8Palette.yellow
                                                      .withValues(
                                                          alpha: 0.5),
                                                  blurRadius: shadowBlur,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                                SizedBox(height: spacing * 0.8),

                                // "INSERT COIN" flavor text
                                FadeTransition(
                                  opacity: _promptFade,
                                  child: Text(
                                    'INSERT COIN',
                                    style: TextStyle(
                                      fontFamily: 'PressStart2P',
                                      fontSize: smallSize * 0.9,
                                      color: Pico8Palette.darkGrey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Layer 4: BACK button (bottom-left)
                    Positioned(
                      bottom: spacing,
                      left: spacing,
                      child: FadeTransition(
                        opacity: _backFade,
                        child: GestureDetector(
                          onTap: widget.onQuit,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '< BACK',
                              style: TextStyle(
                                fontFamily: 'PressStart2P',
                                fontSize: smallSize,
                                color: Pico8Palette.lavender,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Layer 5: CRT vignette
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: const _CrtVignettePainter(),
                        ),
                      ),
                    ),

                    // Layer 6: Tap flash overlay
                    if (tapVal > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: Pico8Palette.white.withValues(
                              alpha: tapVal < 0.3
                                  ? 0.8 * (tapVal / 0.3)
                                  : 0.8 * (1.0 - (tapVal - 0.3) / 0.7),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitleLetter(
    String letter,
    int index,
    int total,
    double fontSize,
    double glowBlur,
    double glowAlpha,
  ) {
    // Each letter staggers in during the entrance
    // Title letters occupy interval 0.25..0.55 of entrance
    const titleStart = 0.25;
    const titleEnd = 0.55;
    final letterDelay =
        titleStart + (titleEnd - titleStart) * (index / total);
    final letterProgress =
        ((_entranceController.value - letterDelay) / 0.08).clamp(0.0, 1.0);

    final curve = Curves.easeOutCubic.transform(letterProgress);

    return Opacity(
      opacity: curve,
      child: Transform.translate(
        offset: Offset(0, 8.0 * (1.0 - curve)),
        child: Text(
          letter,
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: fontSize,
            color: widget.accentColor,
            shadows: [
              Shadow(
                color: widget.accentColor.withValues(alpha: glowAlpha),
                blurRadius: glowBlur,
              ),
              Shadow(
                color: widget.accentColor.withValues(alpha: 0.2),
                blurRadius: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wider pixel divider with brightness focused inward.
class _PixelDivider extends StatelessWidget {
  const _PixelDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // 9 dots, center brightest, fading outward
    const count = 9;
    final center = count ~/ 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < count; i++) ...[
          Container(
            width: 4,
            height: 4,
            color: color.withValues(
              alpha: 0.15 + 0.85 * (1.0 - (i - center).abs() / center),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// Floating pixel particles drifting upward.
class _PixelParticlePainter extends CustomPainter {
  _PixelParticlePainter({
    required this.animation,
    required this.accentColor,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color accentColor;

  static const int _particleCount = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);

    for (int i = 0; i < _particleCount; i++) {
      final x = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final pxSize = rng.nextBool() ? 3.0 : 4.0;
      final wobbleAmp = 10.0 + rng.nextDouble() * 10.0;

      // Vertical position (wraps)
      final y = (baseY + animation.value * speed) % 1.0;

      // Horizontal wobble
      final dx = math.sin((animation.value * 2 * math.pi) + i * 1.7) *
          wobbleAmp /
          size.width;
      final px = (x + dx) % 1.0;

      // Fade at edges
      final edgeFade = (1.0 - (2.0 * (y - 0.5)).abs()).clamp(0.0, 1.0);
      final alpha = edgeFade * 0.4;
      if (alpha < 0.01) continue;

      // Color: alternate between accent variants and dark grey
      final Color particleColor;
      switch (i % 3) {
        case 0:
          particleColor = accentColor.withValues(alpha: alpha);
        case 1:
          particleColor = accentColor.withValues(alpha: alpha * 0.4);
        default:
          particleColor = Pico8Palette.darkGrey.withValues(alpha: alpha);
      }

      canvas.drawRect(
        Rect.fromLTWH(
          px * size.width,
          y * size.height,
          pxSize,
          pxSize,
        ),
        Paint()..color = particleColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelParticlePainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}

/// Semi-transparent horizontal scanlines for a CRT monitor effect.
class _CrtScanlinePainter extends CustomPainter {
  const _CrtScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Pico8Palette.black.withValues(alpha: 0.10);
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

/// Radial vignette darkening screen edges like a CRT tube.
class _CrtVignettePainter extends CustomPainter {
  const _CrtVignettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Pico8Palette.black.withValues(alpha: 0.0),
        Pico8Palette.black.withValues(alpha: 0.0),
        Pico8Palette.black.withValues(alpha: 0.6),
      ],
      stops: const [0.0, 0.6, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
