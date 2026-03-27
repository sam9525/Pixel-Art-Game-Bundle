import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------

enum _GameState { waiting, flying, landed, crashed, gameOver }

// ---------------------------------------------------------------------------
// Terrain segment
// ---------------------------------------------------------------------------

class _TerrainPoint {
  const _TerrainPoint(this.x, this.y);
  final double x;
  final double y;
}

// ---------------------------------------------------------------------------
// Lunar Lander — classic moon landing physics game
// ---------------------------------------------------------------------------

/// Land the spacecraft safely on the landing pad.
///
/// Controls: Tap left/right thirds of screen for lateral thrust,
/// tap centre for main thruster. Keyboard: Arrow keys / WASD.
class LunarLanderGame extends BaseArcadeGame with TapCallbacks, KeyboardEvents {
  LunarLanderGame() : super(gameId: 'lunar_lander');

  // --- Physics constants (tuned for 256x240 canvas) ---
  static const double _baseGravity = 20.0;
  static const double _mainThrust = 40.0;
  static const double _lateralThrust = 16.0;
  static const double _maxVy = 80.0;
  static const double _maxVx = 60.0;
  static const double _safeVy = 15.0;
  static const double _safeVx = 10.0;
  static const double _startFuel = 100.0;
  static const double _mainFuelRate = 15.0;
  static const double _lateralFuelRate = 5.0;

  // --- Lander dimensions ---
  static const double _landerW = 20.0;
  static const double _landerH = 16.0;
  static const double _hitboxW = 16.0;

  // --- Terrain generation ---
  static const double _terrainMinY = 140.0;
  static const double _terrainMaxY = 210.0;
  static const double _basePadWidth = 50.0;
  static const double _minPadWidth = 30.0;

  // --- Level scaling ---
  static const double _gravityPerLevel = 2.0;
  static const double _fuelPerLevel = 5.0;
  static const double _padShrinkPerLevel = 4.0;

  // --- Timing ---
  static const double _landedPause = 2.0;
  static const double _crashPause = 1.5;

  final Random _rng = Random();

  // --- Game state ---
  _GameState _state = _GameState.waiting;
  int _level = 1;
  double _lx = 0; // lander x (centre)
  double _ly = 0; // lander y (top)
  double _vx = 0;
  double _vy = 0;
  double _fuel = _startFuel;
  double _gravity = _baseGravity;
  double _padWidth = _basePadWidth;
  double _pauseTimer = 0;

  // Thrust state
  bool _thrustMain = false;
  bool _thrustLeft = false;
  bool _thrustRight = false;

  // Terrain
  final List<_TerrainPoint> _terrain = [];
  double _padCentreX = 128;
  double _padY = 200;

  // Visual effects
  double _thrustFlicker = 0;
  final List<_Particle> _particles = [];

  // Stars (static backdrop)
  final List<Offset> _stars = [];

  late SharedScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = SharedScreenFlash(size: res.clone());

    _generateStars();

    world.addAll([
      _StarRenderer(game: this),
      _TerrainRenderer(game: this),
      _LanderRenderer(game: this),
      _ParticleRenderer(game: this),
      _HudRenderer(game: this),
      _screenFlash,
    ]);

    _resetState();
  }

  void _generateStars() {
    _stars.clear();
    final res = BaseArcadeGame.resolution;
    for (int i = 0; i < 60; i++) {
      _stars.add(
        Offset(
          _rng.nextDouble() * res.x,
          _rng.nextDouble() * (_terrainMinY - 10),
        ),
      );
    }
  }

  void _generateTerrain() {
    _terrain.clear();
    final res = BaseArcadeGame.resolution;
    final w = res.x;

    // Determine pad position and width for this level
    _padWidth = (_basePadWidth - _padShrinkPerLevel * (_level - 1)).clamp(
      _minPadWidth,
      _basePadWidth,
    );
    _padCentreX = _padWidth / 2 + _rng.nextDouble() * (w - _padWidth);

    final padLeft = _padCentreX - _padWidth / 2;
    final padRight = _padCentreX + _padWidth / 2;

    // Pad Y: random within lower terrain range
    _padY =
        _terrainMinY +
        30 +
        _rng.nextDouble() * (_terrainMaxY - _terrainMinY - 30);

    // Build terrain points using midpoint displacement
    // Start with endpoints and pad flat section
    final List<_TerrainPoint> rawPoints = [];

    // Generate left section
    rawPoints.addAll(
      _midpointDisplacement(
        0,
        _terrainMinY + _rng.nextDouble() * 40,
        padLeft,
        _padY,
        3,
      ),
    );

    // Flat landing pad
    rawPoints.add(_TerrainPoint(padLeft, _padY));
    rawPoints.add(_TerrainPoint(padRight, _padY));

    // Generate right section
    rawPoints.addAll(
      _midpointDisplacement(
        padRight,
        _padY,
        w,
        _terrainMinY + _rng.nextDouble() * 40,
        3,
      ),
    );

    // Sort by x and add ground bottom
    rawPoints.sort((a, b) => a.x.compareTo(b.x));
    _terrain
      ..clear()
      ..addAll(rawPoints);
  }

  List<_TerrainPoint> _midpointDisplacement(
    double x1,
    double y1,
    double x2,
    double y2,
    int depth,
  ) {
    if (depth <= 0 || (x2 - x1) < 8) {
      return [_TerrainPoint(x1, y1), _TerrainPoint(x2, y2)];
    }
    final mx = (x1 + x2) / 2;
    final my = ((y1 + y2) / 2) + (_rng.nextDouble() - 0.5) * (x2 - x1) * 0.4;
    final clampedMy = my.clamp(_terrainMinY, _terrainMaxY);
    final left = _midpointDisplacement(x1, y1, mx, clampedMy, depth - 1);
    final right = _midpointDisplacement(mx, clampedMy, x2, y2, depth - 1);
    return [...left, ...right.skip(1)];
  }

  void _resetState() {
    final res = BaseArcadeGame.resolution;
    _lx = res.x / 2;
    _ly = 30;
    _vx = 0;
    _vy = 0;
    _gravity = _baseGravity + _gravityPerLevel * (_level - 1);
    _fuel = (_startFuel - _fuelPerLevel * (_level - 1)).clamp(40.0, _startFuel);
    _thrustMain = false;
    _thrustLeft = false;
    _thrustRight = false;
    _pauseTimer = 0;
    _thrustFlicker = 0;
    _particles.clear();

    _generateTerrain();
    _state = _GameState.waiting;
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);

    // Update particles
    _updateParticles(dt);

    switch (_state) {
      case _GameState.waiting:
        // Gentle bob
        break;
      case _GameState.flying:
        _updateFlying(dt);
        break;
      case _GameState.landed:
        _pauseTimer += dt;
        if (_pauseTimer >= _landedPause) {
          _level++;
          _resetState();
          _state = _GameState.waiting;
        }
        break;
      case _GameState.crashed:
        _pauseTimer += dt;
        if (_pauseTimer >= _crashPause) {
          if (lives <= 0) {
            _state = _GameState.gameOver;
            onGameOver();
          } else {
            _resetState();
          }
        }
        break;
      case _GameState.gameOver:
        break;
    }
  }

  void _updateFlying(double dt) {
    // Apply gravity
    _vy += _gravity * dt;

    // Apply thrust
    if (_thrustMain && _fuel > 0) {
      _vy -= _mainThrust * dt;
      _fuel -= _mainFuelRate * dt;
      _spawnThrustParticles(0, 1, 3); // downward
    }
    if (_thrustLeft && _fuel > 0) {
      _vx += _lateralThrust * dt;
      _fuel -= _lateralFuelRate * dt;
      _spawnThrustParticles(-1, 0, 1);
    }
    if (_thrustRight && _fuel > 0) {
      _vx -= _lateralThrust * dt;
      _fuel -= _lateralFuelRate * dt;
      _spawnThrustParticles(1, 0, 1);
    }

    _fuel = _fuel.clamp(0, _startFuel);

    // Clamp velocities
    _vx = _vx.clamp(-_maxVx, _maxVx);
    _vy = _vy.clamp(-_maxVy, _maxVy);

    // Move
    _lx += _vx * dt;
    _ly += _vy * dt;

    // Wrap horizontally
    final res = BaseArcadeGame.resolution;
    if (_lx < -_landerW / 2) _lx = res.x + _landerW / 2;
    if (_lx > res.x + _landerW / 2) _lx = -_landerW / 2;

    // Ceiling
    if (_ly < 0) {
      _ly = 0;
      _vy = _vy.abs() * 0.3;
    }

    // Thrust flicker for animation
    _thrustFlicker += dt * 20;

    // Check collision with terrain
    _checkTerrainCollision();
  }

  void _checkTerrainCollision() {
    final landerBottom = _ly + _landerH;
    final landerLeft = _lx - _hitboxW / 2;
    final landerRight = _lx + _hitboxW / 2;

    // Check each terrain segment
    for (int i = 0; i < _terrain.length - 1; i++) {
      final p1 = _terrain[i];
      final p2 = _terrain[i + 1];

      // Skip segments that don't horizontally overlap with lander
      if (p2.x < landerLeft || p1.x > landerRight) continue;

      // Find terrain height at lander position (interpolate)
      final terrainY = _terrainYAt(_lx, p1, p2);

      if (landerBottom >= terrainY) {
        // Collision! Check if on landing pad and within safe speeds
        final padLeft = _padCentreX - _padWidth / 2;
        final padRight = _padCentreX + _padWidth / 2;

        final onPad = landerLeft >= padLeft - 2 && landerRight <= padRight + 2;
        final safeSpeed = _vy.abs() <= _safeVy && _vx.abs() <= _safeVx;

        if (onPad && safeSpeed) {
          _onLanded();
        } else {
          _onCrash();
        }
        return;
      }
    }
  }

  double _terrainYAt(double x, _TerrainPoint p1, _TerrainPoint p2) {
    if ((p2.x - p1.x).abs() < 0.1) return p1.y;
    final t = ((x - p1.x) / (p2.x - p1.x)).clamp(0.0, 1.0);
    return p1.y + t * (p2.y - p1.y);
  }

  void _onLanded() {
    _state = _GameState.landed;
    _ly = _padY - _landerH;
    _vx = 0;
    _vy = 0;
    _pauseTimer = 0;

    // Score: base points + fuel bonus
    final fuelBonus = (_fuel * 5).round();
    final levelBonus = _level * 100;
    score += 200 + levelBonus + fuelBonus;
  }

  void _onCrash() {
    _state = _GameState.crashed;
    _vx = 0;
    _vy = 0;
    _pauseTimer = 0;
    lives -= 1;
    _screenFlash.trigger();

    // Spawn explosion particles
    for (int i = 0; i < 20; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 20 + _rng.nextDouble() * 60;
      _particles.add(
        _Particle(
          x: _lx,
          y: _ly + _landerH / 2,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed - 20,
          life: 0.5 + _rng.nextDouble() * 0.8,
          color: [
            Pico8Palette.red,
            Pico8Palette.orange,
            Pico8Palette.yellow,
          ][_rng.nextInt(3)],
        ),
      );
    }
  }

  void _spawnThrustParticles(double dirX, double dirY, int count) {
    for (int i = 0; i < count; i++) {
      final spread = (_rng.nextDouble() - 0.5) * 10;
      _particles.add(
        _Particle(
          x: _lx + dirX * -8 + (dirY != 0 ? spread : 0),
          y: _ly + _landerH + dirY * -4 + (dirX != 0 ? spread : 0),
          vx: dirX * (20 + _rng.nextDouble() * 30) + spread,
          vy: dirY * (20 + _rng.nextDouble() * 30),
          life: 0.2 + _rng.nextDouble() * 0.3,
          color: [
            Pico8Palette.orange,
            Pico8Palette.yellow,
            Pico8Palette.red,
          ][_rng.nextInt(3)],
        ),
      );
    }
  }

  void _updateParticles(double dt) {
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 15 * dt; // light gravity on particles
      p.elapsed += dt;
    }
    _particles.removeWhere((p) => p.elapsed >= p.life);
  }

  // --- Input: Touch ---

  @override
  void onTapDown(TapDownEvent event) {
    if (_state == _GameState.waiting) {
      _state = _GameState.flying;
      return;
    }
    if (_state != _GameState.flying) return;

    final res = BaseArcadeGame.resolution;
    final localX = event.localPosition.x;

    // Left third = left thrust, right third = right thrust, centre = main
    final third = res.x / 3;
    if (localX < third) {
      _thrustLeft = true;
    } else if (localX > third * 2) {
      _thrustRight = true;
    } else {
      _thrustMain = true;
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    _thrustMain = false;
    _thrustLeft = false;
    _thrustRight = false;
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _thrustMain = false;
    _thrustLeft = false;
    _thrustRight = false;
  }

  // --- Input: Keyboard ---

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (_state == _GameState.waiting && event is KeyDownEvent) {
      _state = _GameState.flying;
      return KeyEventResult.handled;
    }

    if (_state != _GameState.flying) return KeyEventResult.ignored;

    _thrustMain =
        keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);
    _thrustLeft =
        keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    _thrustRight =
        keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);

    return KeyEventResult.handled;
  }

  // --- Lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _level = 1;
    _resetState();
  }

  @override
  void onGameOver() {
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Particle data
// ---------------------------------------------------------------------------

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
  });

  double x, y, vx, vy;
  final double life;
  double elapsed = 0;
  final Color color;
}

// ---------------------------------------------------------------------------
// Star field renderer
// ---------------------------------------------------------------------------

class _StarRenderer extends PositionComponent {
  _StarRenderer({required this.game});
  final LunarLanderGame game;

  final Paint _dimStar = Paint()..color = Pico8Palette.darkGrey;
  final Paint _brightStar = Paint()..color = Pico8Palette.lightGrey;

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < game._stars.length; i++) {
      final s = game._stars[i];
      final paint = i % 4 == 0 ? _brightStar : _dimStar;
      canvas.drawRect(Rect.fromLTWH(s.dx, s.dy, 1, 1), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Terrain renderer
// ---------------------------------------------------------------------------

class _TerrainRenderer extends PositionComponent {
  _TerrainRenderer({required this.game});
  final LunarLanderGame game;

  final Paint _terrainFill = Paint()..color = Pico8Palette.darkGrey;
  final Paint _terrainEdge = Paint()
    ..color = Pico8Palette.lightGrey
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final Paint _padPaint = Paint()..color = Pico8Palette.green;
  final Paint _padLight = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 5;

  @override
  void render(Canvas canvas) {
    final terrain = game._terrain;
    if (terrain.length < 2) return;

    final res = BaseArcadeGame.resolution;

    // Fill terrain as a polygon
    final path = Path();
    path.moveTo(terrain.first.x, terrain.first.y);
    for (int i = 1; i < terrain.length; i++) {
      path.lineTo(terrain[i].x, terrain[i].y);
    }
    path.lineTo(res.x, res.y);
    path.lineTo(0, res.y);
    path.close();
    canvas.drawPath(path, _terrainFill);

    // Draw terrain edge
    for (int i = 0; i < terrain.length - 1; i++) {
      canvas.drawLine(
        Offset(terrain[i].x, terrain[i].y),
        Offset(terrain[i + 1].x, terrain[i + 1].y),
        _terrainEdge,
      );
    }

    // Draw landing pad
    final padLeft = game._padCentreX - game._padWidth / 2;
    final padRight = game._padCentreX + game._padWidth / 2;
    final padY = game._padY;

    // Pad surface (bright green line)
    canvas.drawRect(
      Rect.fromLTWH(padLeft, padY - 2, game._padWidth, 2),
      _padPaint,
    );

    // Pad markers (small yellow dots at edges)
    canvas.drawRect(Rect.fromLTWH(padLeft, padY - 4, 2, 4), _padLight);
    canvas.drawRect(Rect.fromLTWH(padRight - 2, padY - 4, 2, 4), _padLight);

    // Blink centre marker when waiting or flying
    if (game._state == _GameState.waiting || game._state == _GameState.flying) {
      final blink =
          (game._thrustFlicker * 0.5).floor() % 2 == 0 ||
          game._state == _GameState.waiting;
      if (blink) {
        final cx = game._padCentreX - 1;
        canvas.drawRect(Rect.fromLTWH(cx, padY - 3, 2, 2), _padLight);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Lander renderer
// ---------------------------------------------------------------------------

class _LanderRenderer extends PositionComponent {
  _LanderRenderer({required this.game});
  final LunarLanderGame game;

  // Lander body colours
  final Paint _body = Paint()..color = Pico8Palette.lightGrey;
  final Paint _cockpit = Paint()..color = Pico8Palette.blue;
  final Paint _leg = Paint()..color = Pico8Palette.darkGrey;
  final Paint _outline = Paint()..color = Pico8Palette.black;
  final Paint _thrustPaint = Paint()..color = Pico8Palette.orange;
  final Paint _thrustBright = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 20;

  @override
  void render(Canvas canvas) {
    if (game._state == _GameState.crashed ||
        game._state == _GameState.gameOver) {
      return;
    }

    final lx = game._lx;
    final ly = game._ly;
    final w = LunarLanderGame._landerW;
    final h = LunarLanderGame._landerH;

    // Centre-based drawing
    final left = lx - w / 2;
    final top = ly;

    // Outline (1px border around body)
    canvas.drawRect(Rect.fromLTWH(left - 1, top - 1, w + 2, h + 2), _outline);

    // Main body: silver rectangle
    canvas.drawRect(Rect.fromLTWH(left + 2, top + 2, w - 4, h - 6), _body);

    // Cockpit window: small blue rectangle
    canvas.drawRect(Rect.fromLTWH(lx - 3, top + 3, 6, 4), _cockpit);

    // Landing legs
    canvas.drawRect(Rect.fromLTWH(left, top + h - 4, 3, 4), _leg);
    canvas.drawRect(Rect.fromLTWH(left + w - 3, top + h - 4, 3, 4), _leg);

    // Foot pads
    canvas.drawRect(Rect.fromLTWH(left - 1, top + h - 1, 5, 1), _leg);
    canvas.drawRect(Rect.fromLTWH(left + w - 4, top + h - 1, 5, 1), _leg);

    // --- Thrust flames ---
    final flicker = game._thrustFlicker.floor() % 3;

    if (game._thrustMain && game._fuel > 0) {
      final flameH = 4.0 + flicker * 2.0;
      final paint = flicker % 2 == 0 ? _thrustPaint : _thrustBright;
      // Main flame (centre bottom)
      canvas.drawRect(Rect.fromLTWH(lx - 3, top + h, 6, flameH), paint);
      canvas.drawRect(
        Rect.fromLTWH(lx - 1, top + h + flameH, 2, 2),
        _thrustBright,
      );
    }

    if (game._thrustLeft && game._fuel > 0) {
      final paint = flicker % 2 == 0 ? _thrustPaint : _thrustBright;
      canvas.drawRect(Rect.fromLTWH(left - 3, top + h / 2, 3, 2), paint);
    }

    if (game._thrustRight && game._fuel > 0) {
      final paint = flicker % 2 == 0 ? _thrustPaint : _thrustBright;
      canvas.drawRect(Rect.fromLTWH(left + w, top + h / 2, 3, 2), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Particle renderer
// ---------------------------------------------------------------------------

class _ParticleRenderer extends PositionComponent {
  _ParticleRenderer({required this.game});
  final LunarLanderGame game;

  @override
  int get priority => 25;

  @override
  void render(Canvas canvas) {
    for (final p in game._particles) {
      final alpha = (1.0 - p.elapsed / p.life).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.drawRect(Rect.fromLTWH(p.x, p.y, 2, 2), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// HUD renderer: fuel, speed, altitude, level info
// ---------------------------------------------------------------------------

class _HudRenderer extends PositionComponent {
  _HudRenderer({required this.game});
  final LunarLanderGame game;

  late final TextPaint _labelPaint;
  late final TextPaint _msgPaint;
  late final TextPaint _smallPaint;

  @override
  int get priority => 50;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _labelPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.darkGrey,
        fontSize: 6,
        fontFamily: 'PressStart2P',
      ),
    );
    _msgPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 8,
        fontFamily: 'PressStart2P',
      ),
    );
    _smallPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.lightGrey,
        fontSize: 6,
        fontFamily: 'PressStart2P',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final res = BaseArcadeGame.resolution;

    // Top-left: FUEL bar
    _labelPaint.render(canvas, 'FUEL', Vector2(4, 4));
    final fuelFrac = game._fuel / LunarLanderGame._startFuel;
    final barW = 50.0;
    // Bar background
    canvas.drawRect(
      Rect.fromLTWH(4, 14, barW, 4),
      Paint()..color = Pico8Palette.darkBlue,
    );
    // Bar fill
    final fuelColor = fuelFrac > 0.3 ? Pico8Palette.green : Pico8Palette.red;
    canvas.drawRect(
      Rect.fromLTWH(4, 14, barW * fuelFrac, 4),
      Paint()..color = fuelColor,
    );

    // Top-right: speed indicators
    final vyText = 'VY:${game._vy.abs().toStringAsFixed(0)}';
    final vxText = 'VX:${game._vx.abs().toStringAsFixed(0)}';
    final vyColor = game._vy.abs() <= LunarLanderGame._safeVy
        ? Pico8Palette.green
        : Pico8Palette.red;
    final vxColor = game._vx.abs() <= LunarLanderGame._safeVx
        ? Pico8Palette.green
        : Pico8Palette.red;

    TextPaint(
      style: TextStyle(color: vyColor, fontSize: 6, fontFamily: 'PressStart2P'),
    ).render(canvas, vyText, Vector2(res.x - 70, 4));
    TextPaint(
      style: TextStyle(color: vxColor, fontSize: 6, fontFamily: 'PressStart2P'),
    ).render(canvas, vxText, Vector2(res.x - 70, 14));

    // Level indicator
    _labelPaint.render(
      canvas,
      'LVL ${game._level}',
      Vector2(res.x / 2 - 16, 4),
    );

    // State messages
    if (game._state == _GameState.waiting) {
      _msgPaint.render(
        canvas,
        'TAP TO START',
        Vector2(res.x / 2 - 52, res.y / 2),
      );
      _smallPaint.render(
        canvas,
        'LAND ON THE PAD',
        Vector2(res.x / 2 - 52, res.y / 2 + 14),
      );
    } else if (game._state == _GameState.landed) {
      _msgPaint.render(
        canvas,
        'LANDED!',
        Vector2(res.x / 2 - 30, res.y / 2 - 20),
      );
      final bonus = (game._fuel * 5).round();
      _smallPaint.render(
        canvas,
        'FUEL BONUS: $bonus',
        Vector2(res.x / 2 - 46, res.y / 2 - 6),
      );
    } else if (game._state == _GameState.crashed) {
      TextPaint(
        style: TextStyle(
          color: Pico8Palette.red,
          fontSize: 8,
          fontFamily: 'PressStart2P',
        ),
      ).render(canvas, 'CRASHED!', Vector2(res.x / 2 - 34, res.y / 2 - 10));
    }

    // Touch zone hints (subtle, only when flying)
    if (game._state == _GameState.flying) {
      final third = res.x / 3;
      // Faint divider lines
      final hintPaint = Paint()..color = Pico8Palette.darkBlue;
      canvas.drawRect(Rect.fromLTWH(third, res.y - 6, 1, 6), hintPaint);
      canvas.drawRect(Rect.fromLTWH(third * 2, res.y - 6, 1, 6), hintPaint);

      // Zone labels at very bottom
      final zonePaint = TextPaint(
        style: TextStyle(
          color: Pico8Palette.darkBlue,
          fontSize: 5,
          fontFamily: 'PressStart2P',
        ),
      );
      zonePaint.render(canvas, '<', Vector2(third / 2 - 2, res.y - 8));
      zonePaint.render(canvas, '^', Vector2(res.x / 2 - 2, res.y - 8));
      zonePaint.render(
        canvas,
        '>',
        Vector2(third * 2 + third / 2 - 2, res.y - 8),
      );
    }
  }
}

