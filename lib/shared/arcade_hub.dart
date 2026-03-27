import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/palette.dart';
import '../core/registry.dart';

// ---------------------------------------------------------------------------
// Color cycle sequence for the animated title
// ---------------------------------------------------------------------------
const List<Color> _titleColors = [
  Pico8Palette.yellow,
  Pico8Palette.orange,
  Pico8Palette.red,
  Pico8Palette.pink,
  Pico8Palette.lavender,
  Pico8Palette.blue,
  Pico8Palette.green,
  Pico8Palette.darkGreen,
];

// ---------------------------------------------------------------------------
// ArcadeHubScreen — top-level StatefulWidget
// ---------------------------------------------------------------------------

/// Main menu screen displaying a responsive grid of available arcade games
/// with animated starfield background, color-cycling title, cinematic
/// staggered-card entrance with floating animation, and CRT effects.
class ArcadeHubScreen extends StatefulWidget {
  const ArcadeHubScreen({super.key});

  @override
  State<ArcadeHubScreen> createState() => _ArcadeHubScreenState();
}

class _ArcadeHubScreenState extends State<ArcadeHubScreen>
    with TickerProviderStateMixin {
  final Map<String, int> _highScores = {};

  @override
  void initState() {
    super.initState();
    _loadHighScores();
  }

  Future<void> _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();
    final scores = <String, int>{};
    for (final entry in gameRegistry.values) {
      final score = prefs.getInt('highscore_${entry.id}');
      if (score != null) {
        scores[entry.id] = score;
      }
    }
    if (mounted) {
      setState(() => _highScores.addAll(scores));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = gameRegistry.values.toList();

    return Scaffold(
      backgroundColor: Pico8Palette.black,
      body: Stack(
        children: [
          // Layer 1: Animated starfield
          const Positioned.fill(child: _Starfield()),

          // Layer 2: CRT vignette
          const Positioned.fill(child: _CrtVignette()),

          // Layer 3: Main content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Animated title
                const _AnimatedTitle(),

                const SizedBox(height: 32),

                // Game grid with staggered entrance
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          constraints.maxWidth >= 700
                              ? 4
                              : constraints.maxWidth >= 500
                                  ? 3
                                  : 2;

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _GameCard(
                            key: ValueKey(entry.id),
                            entry: entry,
                            highScore: _highScores[entry.id],
                            index: index,
                          );
                        },
                      );
                    },
                  ),
                ),

                // Bottom status bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '${entries.length} / 20 GAMES UNLOCKED',
                    style: const TextStyle(
                      fontFamily: 'PressStart2P',
                      fontSize: 7,
                      color: Pico8Palette.darkGrey,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Layer 4: CRT scanline overlay
          const Positioned.fill(
            child: IgnorePointer(child: _CrtScanlines()),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Starfield background
// ---------------------------------------------------------------------------

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.speed,
    required this.brightness,
  });

  double x;
  double y;
  final double speed;
  final double brightness;
}

class _Starfield extends StatefulWidget {
  const _Starfield();

  @override
  State<_Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<_Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Star> _stars;
  final math.Random _rng = math.Random(42);

  @override
  void initState() {
    super.initState();
    _stars = List.generate(50, (_) {
      return _Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        speed: 0.004 + _rng.nextDouble() * 0.012,
        brightness: 0.3 + _rng.nextDouble() * 0.7,
      );
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _controller.repeat();
  }

  void _tick() {
    for (final star in _stars) {
      star.y += star.speed * 0.016 * 60;
      if (star.y > 1.0) {
        star.y -= 1.0;
        star.x = _rng.nextDouble();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarfieldPainter(_stars),
      size: Size.infinite,
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.stars);

  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final color =
          star.brightness > 0.6 ? Pico8Palette.white : Pico8Palette.lightGrey;
      final paint = Paint()..color = color.withValues(alpha: star.brightness);
      canvas.drawRect(
        Rect.fromLTWH(
          star.x * size.width,
          star.y * size.height,
          2,
          2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Animated color-cycling title
// ---------------------------------------------------------------------------

class _AnimatedTitle extends StatefulWidget {
  const _AnimatedTitle();

  @override
  State<_AnimatedTitle> createState() => _AnimatedTitleState();
}

class _AnimatedTitleState extends State<_AnimatedTitle> {
  int _colorOffset = 0;
  Timer? _timer;

  static const String _text = 'PIXEL ARCADE';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) {
        setState(() =>
            _colorOffset = (_colorOffset + 1) % _titleColors.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final titleSize = (screenWidth * 0.05).clamp(14.0, 28.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_text.length, (i) {
        final colorIndex = (i + _colorOffset) % _titleColors.length;
        return Text(
          _text[i],
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: titleSize,
            color: _titleColors[colorIndex],
            shadows: [
              Shadow(
                color: _titleColors[colorIndex].withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Cinematic game card with staggered entrance + floating + glow
// ---------------------------------------------------------------------------

class _GameCard extends StatefulWidget {
  const _GameCard({
    super.key,
    required this.entry,
    this.highScore,
    required this.index,
  });

  final GameEntry entry;
  final int? highScore;
  final int index;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard>
    with TickerProviderStateMixin {
  // Entrance: slide in from left
  late final AnimationController _entranceController;
  late final Animation<double> _slideIn;
  late final Animation<double> _fadeIn;

  // Floating bob after entrance
  late final AnimationController _floatController;

  // Icon breathing
  late final AnimationController _iconBreathController;

  // Shimmer on accent bar
  late final AnimationController _shimmerController;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // Entrance: staggered per card
    final delay = widget.index * 0.15;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _slideIn = Tween<double>(begin: -50, end: 0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(
          delay.clamp(0.0, 1.0),
          (0.5 + delay).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(
          delay.clamp(0.0, 1.0),
          (0.3 + delay).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );

    // Float: starts after entrance completes
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // Icon breathing
    _iconBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    // Shimmer on accent bar
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Start entrance, then float
    Future.delayed(Duration(milliseconds: (delay * 1000).toInt()), () {
      if (mounted) {
        _entranceController.forward();
        _entranceController.addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _floatController.repeat(reverse: true);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    _iconBreathController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    Navigator.pushNamed(context, '/game/${widget.entry.id}');
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.entry.color;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entranceController,
        _floatController,
        _iconBreathController,
        _shimmerController,
      ]),
      builder: (context, child) {
        // Float offset
        final floatY = math.sin(_floatController.value * math.pi) * 6;

        // Icon scale for breathing
        final iconScale =
            1.0 + 0.06 * _iconBreathController.value;

        // Shimmer position
        final shimmerPos = _shimmerController.value;

        // Pressed scale
        final pressScale = _isPressed ? 0.94 : 1.0;

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: Transform.translate(
            offset: Offset(_slideIn.value, floatY),
            child: Opacity(
              opacity: _fadeIn.value,
              child: Transform.scale(
                scale: pressScale,
                child: _buildCard(accentColor, iconScale, shimmerPos),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(Color accentColor, double iconScale, double shimmerPos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardSize = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final iconSize = cardSize * 0.26;
        final titleSize = cardSize * 0.075;
        final scoreLabelSize = cardSize * 0.03;
        final scoreValueSize = cardSize * 0.05;
        final padding = cardSize * 0.08;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12121F),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: _isPressed ? 0.4 : 0.15),
                blurRadius: _isPressed ? 25 : 12,
                spreadRadius: _isPressed ? 2 : 0,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Per-card CRT scanlines
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CustomPaint(
                    painter: _CardScanlinePainter(),
                  ),
                ),
              ),

              // Radial top glow
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.8),
                        radius: 1.2,
                        colors: [
                          accentColor.withValues(alpha: _isPressed ? 0.2 : 0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Main content
              Column(
                children: [
                  // Accent bar with shimmer
                  _AccentBar(color: accentColor, shimmerPos: shimmerPos),

                  // Icon with breathing
                  Expanded(
                    child: Center(
                      child: Transform.scale(
                        scale: iconScale,
                        child: Text(
                          widget.entry.icon,
                          style: TextStyle(
                            fontSize: iconSize,
                            shadows: [
                              Shadow(
                                color: accentColor.withValues(alpha: 0.5),
                                blurRadius: iconSize * 0.3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Title with glow
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: Text(
                      widget.entry.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'PressStart2P',
                        fontSize: titleSize,
                        color: Pico8Palette.white,
                        shadows: [
                          Shadow(
                            color: accentColor.withValues(alpha: 0.8),
                            blurRadius: titleSize * 0.8,
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: padding * 0.6),

                  // Divider dots
                  _DividerDots(color: accentColor, size: cardSize * 0.05),

                  SizedBox(height: padding * 0.6),

                  // LED score display
                  _LedScoreDisplay(
                    highScore: widget.highScore,
                    labelSize: scoreLabelSize,
                    valueSize: scoreValueSize,
                    padding: padding,
                  ),

                  SizedBox(height: padding * 0.8),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccentBar extends StatelessWidget {
  const _AccentBar({required this.color, required this.shimmerPos});

  final Color color;
  final double shimmerPos;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.8),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Shimmer sweep
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment(shimmerPos * 2 - 1, 0),
              widthFactor: 0.3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerDots extends StatelessWidget {
  const _DividerDots({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final opacity = i == 2
            ? 1.0
            : i == 1 || i == 3
                ? 0.6
                : 0.3;
        return Container(
          margin: EdgeInsets.symmetric(horizontal: size * 0.3),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            boxShadow: i == 2
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: size,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _LedScoreDisplay extends StatelessWidget {
  const _LedScoreDisplay({
    this.highScore,
    required this.labelSize,
    required this.valueSize,
    required this.padding,
  });

  final int? highScore;
  final double labelSize;
  final double valueSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: padding),
      padding: EdgeInsets.symmetric(
        horizontal: padding * 0.8,
        vertical: padding * 0.6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF08080F),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: const Color(0xFF1A1A2A),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            'HIGH SCORE',
            style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: labelSize,
              color: const Color(0xFF444444),
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: labelSize * 0.5),
          Text(
            highScore != null
                ? highScore.toString().padLeft(6, '0')
                : '------',
            style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: valueSize,
              color: Pico8Palette.yellow,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: Pico8Palette.yellow.withValues(alpha: 0.8),
                  blurRadius: valueSize * 0.8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Pico8Palette.black.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// CRT vignette overlay
// ---------------------------------------------------------------------------

class _CrtVignette extends StatelessWidget {
  const _CrtVignette();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VignettePainter(),
      size: Size.infinite,
    );
  }
}

class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Pico8Palette.black.withValues(alpha: 0.0),
        Pico8Palette.black.withValues(alpha: 0.0),
        Pico8Palette.black.withValues(alpha: 0.5),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// CRT scanline overlay
// ---------------------------------------------------------------------------

class _CrtScanlines extends StatelessWidget {
  const _CrtScanlines();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanlinePainter(),
      size: Size.infinite,
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Pico8Palette.black.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
