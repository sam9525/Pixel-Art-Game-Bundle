import 'dart:async';
import 'dart:math';

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
/// with animated starfield background, color-cycling title, enhanced game
/// cards, a bottom status bar, and a CRT scanline overlay.
class ArcadeHubScreen extends StatefulWidget {
  const ArcadeHubScreen({super.key});

  @override
  State<ArcadeHubScreen> createState() => _ArcadeHubScreenState();
}

class _ArcadeHubScreenState extends State<ArcadeHubScreen> {
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

          // Layer 2: Main content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Animated title
                const _AnimatedTitle(),

                const SizedBox(height: 24),

                // Game grid
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          constraints.maxWidth >= 600 ? 3 : 2;

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _GameCard(
                            entry: entry,
                            highScore: _highScores[entry.id],
                          );
                        },
                      );
                    },
                  ),
                ),

                // Bottom status bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${entries.length} / 20 GAMES UNLOCKED',
                    style: const TextStyle(
                      fontFamily: 'PressStart2P',
                      fontSize: 8,
                      color: Pico8Palette.darkGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Layer 3: CRT scanline overlay
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
  final Random _rng = Random(42);

  @override
  void initState() {
    super.initState();
    _stars = List.generate(40, (_) {
      return _Star(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        speed: 0.005 + _rng.nextDouble() * 0.015,
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
      star.y += star.speed * 0.016 * 60; // normalize to ~60fps feel
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
      final color = star.brightness > 0.6
          ? Pico8Palette.white
          : Pico8Palette.lightGrey;
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
        setState(() => _colorOffset = (_colorOffset + 1) % _titleColors.length);
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_text.length, (i) {
        final colorIndex =
            (i + _colorOffset) % _titleColors.length;
        return Text(
          _text[i],
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: 24,
            color: _titleColors[colorIndex],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Enhanced game card with accent border, icon, tap animation, high score
// ---------------------------------------------------------------------------

class _GameCard extends StatefulWidget {
  const _GameCard({required this.entry, this.highScore});

  final GameEntry entry;
  final int? highScore;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
    Navigator.pushNamed(context, '/game/${widget.entry.id}');
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Pico8Palette.darkGrey,
            border: Border.all(
              color: Pico8Palette.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Colored accent top border
              Container(
                height: 4,
                color: widget.entry.color,
              ),

              // Icon area
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    widget.entry.icon,
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.entry.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'PressStart2P',
                    fontSize: 12,
                    color: Pico8Palette.white,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // High score
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                child: Text(
                  widget.highScore != null
                      ? 'HIGH SCORE ${widget.highScore}'
                      : 'HIGH SCORE ---',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'PressStart2P',
                    fontSize: 6,
                    color: Pico8Palette.yellow,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      ..color = Pico8Palette.black.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => false;
}
