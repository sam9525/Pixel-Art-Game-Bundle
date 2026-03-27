import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../core/base_game.dart';
import '../core/palette.dart';

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------

enum _GameState { waiting, playing, dying, levelTransition, gameOver }

// ---------------------------------------------------------------------------
// Asteroid size definitions
// ---------------------------------------------------------------------------

enum _AsteroidSize { large, medium, small }

class _AsteroidData {
  _AsteroidData({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.angularVel,
    required this.size,
    required this.vertices,
  });

  double x, y, vx, vy, angle, angularVel;
  final _AsteroidSize size;
  final List<Offset> vertices;
}

// ---------------------------------------------------------------------------
// UFO data
// ---------------------------------------------------------------------------

enum _UfoSize { small, large }

// ---------------------------------------------------------------------------
// Classic Asteroids arcade game with vector-style pixel art.
//
// Controls:
//   Keyboard: Arrow Left/Right or A/D to rotate, Arrow Up or W to thrust,
//             Space to fire
//   Touch: Left side = rotate left, Right side = rotate right,
//          Center tap = fire, Swipe up = thrust
// ---------------------------------------------------------------------------

class AsteroidsGame extends BaseArcadeGame
    with TapCallbacks, DragCallbacks, KeyboardEvents {
  AsteroidsGame() : super(gameId: 'asteroids');

  // --- Layout constants ---
  static const double _shipSize = 8.0;
  static const double _bulletSpeed = 200.0;
  static const double _shipAccel = 120.0;
  static const double _shipDrag = 0.985;
  static const double _shipMaxSpeed = 150.0;
  static const double _shipRotationSpeed = 3.5;
  static const double _bulletLifetime = 1.2;
  static const int _maxBullets = 4;

  static const double _largeAsteroidRadius = 14.0;
  static const double _mediumAsteroidRadius = 7.0;
  static const double _smallAsteroidRadius = 3.5;
  static const double _largeAsteroidSpeed = 30.0;
  static const double _mediumAsteroidSpeed = 50.0;
  static const double _smallAsteroidSpeed = 70.0;

  static const int _pointsLarge = 20;
  static const int _pointsMedium = 50;
  static const int _pointsSmall = 100;
  static const int _pointsUfoSmall = 200;
  static const int _pointsUfoLarge = 1000;

  static const int _startAsteroids = 4;
  static const int _asteroidsPerLevel = 2;
  static const double _extraLifeThreshold = 10000.0;

  static const double _ufoMinInterval = 15.0;
  static const double _ufoMaxInterval = 30.0;
  static const double _ufoWidth = 16.0;
  static const double _ufoHeight = 6.0;
  static const double _ufoSpeed = 50.0;
  static const double _ufoFireInterval = 1.5;
  static const double _ufoBulletSpeed = 80.0;

  static const double _shipInvulnDuration = 2.5;
  static const double _levelTransitionDuration = 2.0;
  static const double _dyingPauseDuration = 1.5;

  final Random _rng = Random();

  // --- Game state ---
  _GameState _gameState = _GameState.waiting;
  int _level = 1;
  double _pauseTimer = 0;
  double _extraLifeAccumulator = 0;

  // Ship state
  double _shipX = 128.0;
  double _shipY = 120.0;
  double _shipAngle = -pi / 2; // pointing up
  double _shipVx = 0.0;
  double _shipVy = 0.0;
  bool _thrusting = false;
  bool _invulnerable = false;
  double _invulnTimer = 0.0;
  double _thrustFlicker = 0.0;
  double _autoFireTimer = 0.0;

  // Bullets
  final List<_BulletData> _bullets = [];

  // Asteroids
  final List<_AsteroidData> _asteroids = [];

  // UFO
  bool _ufoActive = false;
  double _ufoX = 0.0;
  int _ufoDir = 1;
  _UfoSize _ufoSize = _UfoSize.small;
  double _ufoTimer = 0.0;
  double _ufoFireTimer = 0.0;
  final List<Vector2> _ufoBullets = [];

  // Particles
  final List<_Particle> _particles = [];

  // Touch input
  bool _touchRotateLeft = false;
  bool _touchRotateRight = false;
  bool _touchThrust = false;
  double _lastTouchY = 0;

  // Stars (static backdrop)
  final List<Offset> _stars = [];
  final List<double> _starBrightness = [];

  // Effect components
  late _ScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = _ScreenFlash(size: res.clone());

    _generateStars();

    world.addAll([
      _StarRenderer(game: this),
      _ShipRenderer(game: this),
      _AsteroidRenderer(game: this),
      _BulletRenderer(game: this),
      _UfoRenderer(game: this),
      _ParticleRenderer(game: this),
      _HudRenderer(game: this),
      _screenFlash,
    ]);

    _spawnAsteroids(_startAsteroids);
    _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
  }

  void _generateStars() {
    _stars.clear();
    _starBrightness.clear();
    final res = BaseArcadeGame.resolution;
    for (int i = 0; i < 50; i++) {
      _stars.add(Offset(
        _rng.nextDouble() * res.x,
        _rng.nextDouble() * res.y,
      ));
      _starBrightness.add(0.15 + _rng.nextDouble() * 0.35);
    }
  }

  List<Offset> _generateAsteroidVertices(double radius) {
    final List<Offset> verts = [];
    const int count = 8;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * pi * 2;
      final r = radius * (0.7 + _rng.nextDouble() * 0.5);
      verts.add(Offset(cos(angle) * r, sin(angle) * r));
    }
    return verts;
  }

  void _spawnAsteroids(int count) {
    final res = BaseArcadeGame.resolution;
    for (int i = 0; i < count; i++) {
      double ax = _rng.nextDouble() * res.x;
      double ay = _rng.nextDouble() * res.y;
      // Spawn away from the ship
      for (int attempt = 0; attempt < 20; attempt++) {
        ax = _rng.nextDouble() * res.x;
        ay = _rng.nextDouble() * res.y;
        final dx = ax - _shipX;
        final dy = ay - _shipY;
        if (sqrt(dx * dx + dy * dy) > 60) {
          break;
        }
      }

      final speed = _largeAsteroidSpeed * (0.8 + _rng.nextDouble() * 0.5);
      final dir = _rng.nextDouble() * pi * 2;
      _asteroids.add(_AsteroidData(
        x: ax,
        y: ay,
        vx: cos(dir) * speed,
        vy: sin(dir) * speed,
        angle: _rng.nextDouble() * pi * 2,
        angularVel: (_rng.nextDouble() - 0.5) * 2.0,
        size: _AsteroidSize.large,
        vertices: _generateAsteroidVertices(_largeAsteroidRadius),
      ));
    }
  }

  void _spawnChildAsteroids(_AsteroidData parent) {
    final childCount = 2;
    final childRadius = parent.size == _AsteroidSize.large
        ? _mediumAsteroidRadius
        : _smallAsteroidRadius;
    final childSpeed = parent.size == _AsteroidSize.large
        ? _mediumAsteroidSpeed
        : _smallAsteroidSpeed;
    final childSize = parent.size == _AsteroidSize.large
        ? _AsteroidSize.medium
        : _AsteroidSize.small;

    for (int i = 0; i < childCount; i++) {
      final dir = _rng.nextDouble() * pi * 2;
      final speed = childSpeed * (0.8 + _rng.nextDouble() * 0.5);
      _asteroids.add(_AsteroidData(
        x: parent.x,
        y: parent.y,
        vx: cos(dir) * speed,
        vy: sin(dir) * speed,
        angle: _rng.nextDouble() * pi * 2,
        angularVel: (_rng.nextDouble() - 0.5) * 3.0,
        size: childSize,
        vertices: _generateAsteroidVertices(childRadius),
      ));
    }
  }

  void _spawnUfo() {
    _ufoActive = true;
    _ufoDir = _rng.nextBool() ? 1 : -1;
    _ufoX = _ufoDir == 1 ? -_ufoWidth : 256 + _ufoWidth;
    _ufoSize = _rng.nextBool() ? _UfoSize.small : _UfoSize.large;
    _ufoFireTimer = _ufoFireInterval;
  }

  void _fireBullet() {
    if (_bullets.length >= _maxBullets) return;
    final speed = _bulletSpeed;
    _bullets.add(_BulletData(
      x: _shipX + cos(_shipAngle) * _shipSize * 0.6,
      y: _shipY + sin(_shipAngle) * _shipSize * 0.6,
      vx: cos(_shipAngle) * speed + _shipVx * 0.3,
      vy: sin(_shipAngle) * speed + _shipVy * 0.3,
      life: _bulletLifetime,
    ));
  }

  void _fireUfoBullet() {
    if (!_ufoActive) return;
    final targetX = _shipX;
    final targetY = _shipY;
    final ufoCx = _ufoX + _ufoWidth / 2;
    final ufoCy = 20.0;
    final angle = atan2(targetY - ufoCy, targetX - ufoCx);
    _ufoBullets.add(Vector2(
      ufoCx + cos(angle) * 4,
      ufoCy + sin(angle) * 4,
    ));
    // Store velocity separately since we don't have a data class
    _ufoBulletsVel.add(Vector2(
      cos(angle) * _ufoBulletSpeed,
      sin(angle) * _ufoBulletSpeed,
    ));
  }

  final List<Vector2> _ufoBulletsVel = [];

  void _explodeAsteroid(_AsteroidData asteroid) {
    final pts = asteroid.size == _AsteroidSize.large
        ? _pointsLarge
        : asteroid.size == _AsteroidSize.medium
            ? _pointsMedium
            : _pointsSmall;
    score += pts;

    // Check extra life
    _extraLifeAccumulator += pts;
    if (_extraLifeAccumulator >= _extraLifeThreshold) {
      _extraLifeAccumulator -= _extraLifeThreshold;
      lives += 1;
    }

    // Spawn particles
    final color = asteroid.size == _AsteroidSize.large
        ? Pico8Palette.lightGrey
        : asteroid.size == _AsteroidSize.medium
            ? Pico8Palette.lightGrey
            : Pico8Palette.lightGrey;
    for (int i = 0; i < 6; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 20 + _rng.nextDouble() * 40;
      _particles.add(_Particle(
        x: asteroid.x,
        y: asteroid.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: 0.4 + _rng.nextDouble() * 0.4,
        color: color,
      ));
    }

    // Score popup
    world.add(_ScorePopup(
      position: Vector2(asteroid.x, asteroid.y),
      points: pts,
    ));

    // Explosion flash
    final radius = asteroid.size == _AsteroidSize.large
        ? _largeAsteroidRadius
        : asteroid.size == _AsteroidSize.medium
            ? _mediumAsteroidRadius
            : _smallAsteroidRadius;
    world.add(_AsteroidExplosion(
      center: Offset(asteroid.x, asteroid.y),
      radius: radius,
    ));
  }

  void _hitShip() {
    if (_invulnerable) return;
    lives -= 1;
    _screenFlash.trigger();

    // Explosion particles
    for (int i = 0; i < 25; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 20 + _rng.nextDouble() * 60;
      _particles.add(_Particle(
        x: _shipX,
        y: _shipY,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: 0.5 + _rng.nextDouble() * 0.8,
        color: [Pico8Palette.orange, Pico8Palette.yellow, Pico8Palette.red][_rng.nextInt(3)],
      ));
    }

    if (lives <= 0) {
      _gameState = _GameState.gameOver;
      onGameOver();
    } else {
      _gameState = _GameState.dying;
      _pauseTimer = _dyingPauseDuration;
      _invulnerable = true;
      _invulnTimer = _shipInvulnDuration;
    }
  }

  void _respawnShip() {
    _shipX = 128.0;
    _shipY = 120.0;
    _shipAngle = -pi / 2;
    _shipVx = 0;
    _shipVy = 0;
    _thrusting = false;
    _invulnerable = true;
    _invulnTimer = _shipInvulnDuration;
  }

  void _nextLevel() {
    _level++;
    _bullets.clear();
    _ufoBullets.clear();
    _ufoBulletsVel.clear();
    _ufoActive = false;
    _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
    _spawnAsteroids(_startAsteroids + _asteroidsPerLevel * (_level - 1));
    _respawnShip();
    _gameState = _GameState.playing;
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);

    if (_gameState == _GameState.dying) {
      _pauseTimer -= dt;
      _updateParticles(dt);
      if (_pauseTimer <= 0) {
        _respawnShip();
        _gameState = _GameState.playing;
      }
      return;
    }

    if (_gameState == _GameState.levelTransition) {
      _pauseTimer -= dt;
      _updateParticles(dt);
      if (_pauseTimer <= 0) {
        _nextLevel();
      }
      return;
    }

    if (_gameState == _GameState.gameOver) {
      _updateParticles(dt);
      return;
    }

    if (_gameState == _GameState.waiting) {
      _updateParticles(dt);
      return;
    }

    // --- Playing ---
    _updateShip(dt);
    _autoFireTimer -= dt;
    if (_autoFireTimer <= 0) {
      _autoFireTimer = 0.2;
      _fireBullet();
    }
    _updateBullets(dt);
    _updateAsteroids(dt);
    _updateUfo(dt);
    _updateUfoBullets(dt);
    _updateParticles(dt);
    _checkCollisions();

    if (_invulnerable) {
      _invulnTimer -= dt;
      if (_invulnTimer <= 0) {
        _invulnerable = false;
      }
    }

    // Level clear?
    if (_asteroids.isEmpty) {
      _gameState = _GameState.levelTransition;
      _pauseTimer = _levelTransitionDuration;
    }
  }

  void _updateShip(double dt) {
    // Rotation
    double rotateInput = 0;
    if (_touchRotateLeft) rotateInput -= 1;
    if (_touchRotateRight) rotateInput += 1;

    _shipAngle += rotateInput * _shipRotationSpeed * dt;

    // Thrust
    if (_thrusting || _touchThrust) {
      _shipVx += cos(_shipAngle) * _shipAccel * dt;
      _shipVy += sin(_shipAngle) * _shipAccel * dt;
      _thrustFlicker += dt * 20;

      // Thrust particles
      if (_rng.nextDouble() < 0.4) {
        final backAngle = _shipAngle + pi;
        _particles.add(_Particle(
          x: _shipX + cos(backAngle) * _shipSize * 0.4,
          y: _shipY + sin(backAngle) * _shipSize * 0.4,
          vx: cos(backAngle) * (30 + _rng.nextDouble() * 20) + _shipVx * 0.5,
          vy: sin(backAngle) * (30 + _rng.nextDouble() * 20) + _shipVy * 0.5,
          life: 0.15 + _rng.nextDouble() * 0.2,
          color: _rng.nextBool() ? Pico8Palette.orange : Pico8Palette.yellow,
        ));
      }
    }

    // Apply drag
    _shipVx *= _shipDrag;
    _shipVy *= _shipDrag;

    // Clamp speed
    final speed = sqrt(_shipVx * _shipVx + _shipVy * _shipVy);
    if (speed > _shipMaxSpeed) {
      _shipVx = (_shipVx / speed) * _shipMaxSpeed;
      _shipVy = (_shipVy / speed) * _shipMaxSpeed;
    }

    // Move
    _shipX += _shipVx * dt;
    _shipY += _shipVy * dt;

    // Wrap around screen
    final res = BaseArcadeGame.resolution;
    if (_shipX < -_shipSize) _shipX = res.x + _shipSize;
    if (_shipX > res.x + _shipSize) _shipX = -_shipSize;
    if (_shipY < -_shipSize) _shipY = res.y + _shipSize;
    if (_shipY > res.y + _shipSize) _shipY = -_shipSize;
  }

  void _updateBullets(double dt) {
    for (int i = _bullets.length - 1; i >= 0; i--) {
      final b = _bullets[i];
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.life -= dt;

      // Wrap
      final res = BaseArcadeGame.resolution;
      if (b.x < 0) b.x += res.x;
      if (b.x > res.x) b.x -= res.x;
      if (b.y < 0) b.y += res.y;
      if (b.y > res.y) b.y -= res.y;

      if (b.life <= 0) {
        _bullets.removeAt(i);
      }
    }
  }

  void _updateAsteroids(double dt) {
    final res = BaseArcadeGame.resolution;
    for (final a in _asteroids) {
      a.x += a.vx * dt;
      a.y += a.vy * dt;
      a.angle += a.angularVel * dt;

      // Wrap
      if (a.x < -_largeAsteroidRadius) a.x += res.x + _largeAsteroidRadius * 2;
      if (a.x > res.x + _largeAsteroidRadius) a.x -= res.x + _largeAsteroidRadius * 2;
      if (a.y < -_largeAsteroidRadius) a.y += res.y + _largeAsteroidRadius * 2;
      if (a.y > res.y + _largeAsteroidRadius) a.y -= res.y + _largeAsteroidRadius * 2;
    }
  }

  void _updateUfo(double dt) {
    if (_ufoActive) {
      _ufoX += _ufoDir * _ufoSpeed * dt;
      if (_ufoX < -_ufoWidth || _ufoX > 256 + _ufoWidth) {
        _ufoActive = false;
        _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
        return;
      }

      // UFO firing
      _ufoFireTimer -= dt;
      if (_ufoFireTimer <= 0) {
        _ufoFireTimer = _ufoFireInterval;
        _fireUfoBullet();
      }
    } else {
      _ufoTimer -= dt;
      if (_ufoTimer <= 0) {
        _spawnUfo();
      }
    }
  }

  void _updateUfoBullets(double dt) {
    for (int i = _ufoBullets.length - 1; i >= 0; i--) {
      _ufoBullets[i].x += _ufoBulletsVel[i].x * dt;
      _ufoBullets[i].y += _ufoBulletsVel[i].y * dt;

      if (_ufoBullets[i].y > 245) {
        _ufoBullets.removeAt(i);
        _ufoBulletsVel.removeAt(i);
        continue;
      }
      if (_ufoBullets[i].x < 0 || _ufoBullets[i].x > 256) {
        _ufoBullets.removeAt(i);
        _ufoBulletsVel.removeAt(i);
      }
    }
  }

  void _updateParticles(double dt) {
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.elapsed += dt;
    }
    _particles.removeWhere((p) => p.elapsed >= p.life);
  }

  // --- Collision detection ---

  void _checkCollisions() {
    _checkBulletsVsAsteroids();
    _checkBulletsVsUfo();
    _checkShipVsAsteroids();
    _checkUfoBulletsVsShip();
  }

  void _checkBulletsVsAsteroids() {
    for (int bi = _bullets.length - 1; bi >= 0; bi--) {
      final bullet = _bullets[bi];

      for (int ai = _asteroids.length - 1; ai >= 0; ai--) {
        final asteroid = _asteroids[ai];
        final radius = asteroid.size == _AsteroidSize.large
            ? _largeAsteroidRadius
            : asteroid.size == _AsteroidSize.medium
                ? _mediumAsteroidRadius
                : _smallAsteroidRadius;

        final dx = bullet.x - asteroid.x;
        final dy = bullet.y - asteroid.y;
        if (dx * dx + dy * dy < radius * radius) {
          // Hit!
          _explodeAsteroid(asteroid);
          _spawnChildAsteroids(asteroid);
          _asteroids.removeAt(ai);
          _bullets.removeAt(bi);
          break;
        }
      }
    }
  }

  void _checkBulletsVsUfo() {
    if (!_ufoActive) return;
    for (int bi = _bullets.length - 1; bi >= 0; bi--) {
      final bullet = _bullets[bi];
      final ufoRect = Rect.fromLTWH(_ufoX, 17.0, _ufoWidth, _ufoHeight);

      if (ufoRect.contains(Offset(bullet.x, bullet.y))) {
        final pts = _ufoSize == _UfoSize.small
            ? _pointsUfoSmall
            : _pointsUfoLarge;
        score += pts;

        // Extra life check
        _extraLifeAccumulator += pts;
        if (_extraLifeAccumulator >= _extraLifeThreshold) {
          _extraLifeAccumulator -= _extraLifeThreshold;
          lives += 1;
        }

        world.add(_ScorePopup(
          position: Vector2(_ufoX + _ufoWidth / 2, 20.0),
          points: pts,
        ));

        // Explosion
        for (int i = 0; i < 12; i++) {
          final angle = _rng.nextDouble() * pi * 2;
          final speed = 20 + _rng.nextDouble() * 40;
          _particles.add(_Particle(
            x: _ufoX + _ufoWidth / 2,
            y: 20.0,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            life: 0.4 + _rng.nextDouble() * 0.4,
            color: Pico8Palette.pink,
          ));
        }

        world.add(_AsteroidExplosion(
          center: Offset(_ufoX + _ufoWidth / 2, 20.0),
          radius: _ufoWidth / 2,
        ));

        _ufoActive = false;
        _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
        _bullets.removeAt(bi);
        break;
      }
    }
  }

  void _checkShipVsAsteroids() {
    if (_invulnerable) return;

    for (final asteroid in _asteroids) {
      final radius = asteroid.size == _AsteroidSize.large
          ? _largeAsteroidRadius
          : asteroid.size == _AsteroidSize.medium
              ? _mediumAsteroidRadius
              : _smallAsteroidRadius;

      // Simple circle collision with ship center
      final dx = _shipX - asteroid.x;
      final dy = _shipY - asteroid.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < radius + _shipSize * 0.4) {
        _hitShip();
        return;
      }
    }
  }

  void _checkUfoBulletsVsShip() {
    if (_invulnerable) return;
    for (int i = _ufoBullets.length - 1; i >= 0; i--) {
      final bullet = _ufoBullets[i];
      final dx = bullet.x - _shipX;
      final dy = bullet.y - _shipY;
      if (dx * dx + dy * dy < 16) {
        _ufoBullets.removeAt(i);
        _ufoBulletsVel.removeAt(i);
        _hitShip();
        return;
      }
    }
  }

  // --- Input: Touch ---

  @override
  void onTapDown(TapDownEvent event) {
    if (_gameState == _GameState.waiting) {
      _gameState = _GameState.playing;
      return;
    }
    if (_gameState != _GameState.playing) return;

    final res = BaseArcadeGame.resolution;
    final localX = event.localPosition.x;

    // Left third = rotate left, right third = rotate right, center = fire
    final third = res.x / 3;
    if (localX < third) {
      _touchRotateLeft = true;
    } else if (localX > third * 2) {
      _touchRotateRight = true;
    } else {
      _fireBullet();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    _touchRotateLeft = false;
    _touchRotateRight = false;
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _touchRotateLeft = false;
    _touchRotateRight = false;
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final pos = event.canvasPosition;
    _lastTouchY = pos.y;
    if (_gameState == _GameState.waiting) {
      _gameState = _GameState.playing;
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_gameState != _GameState.playing) return;

    final res = BaseArcadeGame.resolution;
    final currentX = event.canvasStartPosition.x + event.canvasDelta.x;
    final currentY = event.canvasStartPosition.y + event.canvasDelta.y;

    final third = res.x / 3;
    if (currentX < third) {
      _touchRotateLeft = true;
      _touchRotateRight = false;
    } else if (currentX > third * 2) {
      _touchRotateRight = true;
      _touchRotateLeft = false;
    } else {
      _touchRotateLeft = false;
      _touchRotateRight = false;
    }

    // Swipe up for thrust
    final dy = currentY - _lastTouchY;
    if (dy < -10) {
      _touchThrust = true;
    }
    _lastTouchY = currentY;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _touchRotateLeft = false;
    _touchRotateRight = false;
    _touchThrust = false;
  }

  // --- Input: Keyboard ---

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (_gameState == _GameState.waiting && event is KeyDownEvent) {
      _gameState = _GameState.playing;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        if (_gameState == _GameState.playing) {
          _fireBullet();
        }
      }
    }

    if (_gameState != _GameState.playing) return KeyEventResult.handled;

    _touchRotateLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    _touchRotateRight = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    _touchThrust = keysPressed.contains(LogicalKeyboardKey.arrowUp);

    return KeyEventResult.handled;
  }

  // --- Lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _level = 1;
    _extraLifeAccumulator = 0;
    _bullets.clear();
    _asteroids.clear();
    _ufoBullets.clear();
    _ufoBulletsVel.clear();
    _particles.clear();
    _gameState = _GameState.waiting;
    _invulnerable = false;
    _thrusting = false;
    _autoFireTimer = 0.0;
    _touchRotateLeft = false;
    _touchRotateRight = false;
    _touchThrust = false;
    _spawnAsteroids(_startAsteroids);
    _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
    _ufoActive = false;
    _respawnShip();
  }

  @override
  void onGameOver() {
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Bullet data
// ---------------------------------------------------------------------------

class _BulletData {
  _BulletData({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
  });

  double x, y, vx, vy, life;
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
  final AsteroidsGame game;

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < game._stars.length; i++) {
      final s = game._stars[i];
      canvas.drawRect(
        Rect.fromLTWH(s.dx, s.dy, 1, 1),
        Paint()..color = Pico8Palette.lightGrey.withValues(alpha: game._starBrightness[i]),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ship renderer: triangle outline with thrust flame
// ---------------------------------------------------------------------------

class _ShipRenderer extends PositionComponent {
  _ShipRenderer({required this.game});
  final AsteroidsGame game;

  final Paint _outlinePaint = Paint()
    ..color = Pico8Palette.white
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  final Paint _thrustPaint = Paint()..color = Pico8Palette.orange;
  final Paint _thrustBright = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 20;

  @override
  void render(Canvas canvas) {
    if (game._gameState == _GameState.gameOver) return;

    // Blink during invulnerability
    if (game._invulnerable) {
      final blink = ((game._invulnTimer * 8).toInt()) % 2;
      if (blink == 1) return;
    }

    final cx = game._shipX;
    final cy = game._shipY;
    final angle = game._shipAngle;
    final size = AsteroidsGame._shipSize;

    // Ship points (nose, left wing, right wing, notch at back)
    final noseX = cx + cos(angle) * size;
    final noseY = cy + sin(angle) * size;
    final leftX = cx + cos(angle + 2.5) * size * 0.7;
    final leftY = cy + sin(angle + 2.5) * size * 0.7;
    final rightX = cx + cos(angle - 2.5) * size * 0.7;
    final rightY = cy + sin(angle - 2.5) * size * 0.7;
    final backX = cx + cos(angle + pi) * size * 0.3;
    final backY = cy + sin(angle + pi) * size * 0.3;

    final path = Path()
      ..moveTo(noseX, noseY)
      ..lineTo(leftX, leftY)
      ..lineTo(backX, backY)
      ..lineTo(rightX, rightY)
      ..close();

    canvas.drawPath(path, _outlinePaint);

    // Thrust flame
    if (game._thrusting || game._touchThrust) {
      final flicker = (game._thrustFlicker.floor() % 3);
      final flameLen = 4.0 + flicker * 2.0;
      final backAngle = angle + pi;
      final fx1 = cx + cos(backAngle - 0.3) * size * 0.3;
      final fy1 = cy + sin(backAngle - 0.3) * size * 0.3;
      final fx2 = cx + cos(backAngle + 0.3) * size * 0.3;
      final fy2 = cy + sin(backAngle + 0.3) * size * 0.3;
      final tipX = cx + cos(backAngle) * (size * 0.3 + flameLen);
      final tipY = cy + sin(backAngle) * (size * 0.3 + flameLen);

      final flamePath = Path()
        ..moveTo(fx1, fy1)
        ..lineTo(tipX, tipY)
        ..lineTo(fx2, fy2)
        ..close();

      final paint = flicker % 2 == 0 ? _thrustPaint : _thrustBright;
      canvas.drawPath(flamePath, paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Asteroid renderer: irregular polygon outlines
// ---------------------------------------------------------------------------

class _AsteroidRenderer extends PositionComponent {
  _AsteroidRenderer({required this.game});
  final AsteroidsGame game;

  final Paint _outlinePaint = Paint()
    ..color = Pico8Palette.lightGrey
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  @override
  int get priority => 10;

  @override
  void render(Canvas canvas) {
    for (final asteroid in game._asteroids) {
      final verts = asteroid.vertices;
      if (verts.isEmpty) continue;

      final path = Path();
      final cosA = cos(asteroid.angle);
      final sinA = sin(asteroid.angle);

      for (int i = 0; i < verts.length; i++) {
        final v = verts[i];
        final rx = v.dx * cosA - v.dy * sinA + asteroid.x;
        final ry = v.dx * sinA + v.dy * cosA + asteroid.y;
        if (i == 0) {
          path.moveTo(rx, ry);
        } else {
          path.lineTo(rx, ry);
        }
      }
      path.close();

      canvas.drawPath(path, _outlinePaint);
    }
  }
}

// ---------------------------------------------------------------------------
// Bullet renderer: small bright dots
// ---------------------------------------------------------------------------

class _BulletRenderer extends PositionComponent {
  _BulletRenderer({required this.game});
  final AsteroidsGame game;

  final Paint _ufoBulletPaint = Paint()..color = Pico8Palette.red;

  @override
  int get priority => 15;

  @override
  void render(Canvas canvas) {
    for (final b in game._bullets) {
      final alpha = (b.life / AsteroidsGame._bulletLifetime).clamp(0.3, 1.0);
      final paint = Paint()..color = Pico8Palette.white.withValues(alpha: alpha);
      canvas.drawRect(
        Rect.fromLTWH(b.x - 1, b.y - 1, 2, 2),
        paint,
      );
    }

    for (int i = 0; i < game._ufoBullets.length; i++) {
      final b = game._ufoBullets[i];
      canvas.drawRect(
        Rect.fromLTWH(b.x - 1, b.y - 1, 2, 3),
        _ufoBulletPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// UFO renderer
// ---------------------------------------------------------------------------

class _UfoRenderer extends PositionComponent {
  _UfoRenderer({required this.game});
  final AsteroidsGame game;

  final Paint _bodyPaint = Paint()..color = Pico8Palette.red;
  final Paint _domePaint = Paint()..color = Pico8Palette.pink;
  final Paint _lightPaint = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 12;

  @override
  void render(Canvas canvas) {
    if (!game._ufoActive) return;

    final x = game._ufoX;
    const y = 17.0;
    const w = AsteroidsGame._ufoWidth;
    const h = AsteroidsGame._ufoHeight;

    // UFO body: saucer shape
    canvas.drawRect(Rect.fromLTWH(x + w * 0.25, y, w * 0.5, h * 0.3), _domePaint);
    canvas.drawRect(Rect.fromLTWH(x + w * 0.1, y + h * 0.25, w * 0.8, h * 0.4), _bodyPaint);
    canvas.drawRect(Rect.fromLTWH(x, y + h * 0.6, w, h * 0.4), _bodyPaint);

    // Lights
    canvas.drawRect(Rect.fromLTWH(x + w * 0.2, y + h * 0.3, 2, 1), _lightPaint);
    canvas.drawRect(Rect.fromLTWH(x + w * 0.5 - 1, y + h * 0.3, 2, 1), _lightPaint);
    canvas.drawRect(Rect.fromLTWH(x + w * 0.7, y + h * 0.3, 2, 1), _lightPaint);
  }
}

// ---------------------------------------------------------------------------
// Particle renderer
// ---------------------------------------------------------------------------

class _ParticleRenderer extends PositionComponent {
  _ParticleRenderer({required this.game});
  final AsteroidsGame game;

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
// Asteroid explosion effect
// ---------------------------------------------------------------------------

class _AsteroidExplosion extends PositionComponent {
  _AsteroidExplosion({required Offset center, required this.radius})
      : _centerPos = center;

  final Offset _centerPos;
  final double radius;

  static const double _lifetime = 0.15;
  double _elapsed = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1.0 - _elapsed / _lifetime).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Pico8Palette.white.withValues(alpha: opacity * 0.7);
    canvas.drawCircle(_centerPos, radius * (0.5 + _elapsed / _lifetime * 0.5), paint);
  }
}

// ---------------------------------------------------------------------------
// Score popup: floating "+N" text
// ---------------------------------------------------------------------------

class _ScorePopup extends PositionComponent {
  _ScorePopup({required super.position, required this.points});

  final int points;

  static const double _lifetime = 0.8;
  static const double _driftSpeed = 25.0;

  double _elapsed = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    position.y -= _driftSpeed * dt;
    if (_elapsed >= _lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1.0 - (_elapsed / _lifetime)).clamp(0.0, 1.0);
    final style = TextStyle(
      color: Pico8Palette.yellow.withValues(alpha: opacity),
      fontSize: 6,
      fontFamily: 'PressStart2P',
    );
    TextPaint(style: style).render(canvas, '+$points', Vector2.zero());
  }
}

// ---------------------------------------------------------------------------
// Screen flash on death
// ---------------------------------------------------------------------------

class _ScreenFlash extends RectangleComponent {
  _ScreenFlash({required Vector2 size})
      : super(
          position: Vector2.zero(),
          size: size,
          paint: Paint()..color = Pico8Palette.darkPurple,
          priority: 100,
        );

  double _timer = 0;
  static const double _duration = 0.2;
  bool _active = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint.color = Pico8Palette.darkPurple.withValues(alpha: 0);
  }

  void trigger() {
    _active = true;
    _timer = _duration;
    paint.color = Pico8Palette.darkPurple;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_active) {
      _timer -= dt;
      if (_timer <= 0) {
        _active = false;
        paint.color = Pico8Palette.darkPurple.withValues(alpha: 0);
      } else {
        final opacity = (_timer / _duration).clamp(0.0, 1.0);
        paint.color = Pico8Palette.darkPurple.withValues(alpha: opacity * 0.5);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// HUD: score, lives, level
// ---------------------------------------------------------------------------

class _HudRenderer extends PositionComponent {
  _HudRenderer({required this.game});
  final AsteroidsGame game;

  late final TextPaint _textPaint;
  late final TextPaint _smallPaint;

  @override
  int get priority => 50;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _textPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
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
    super.render(canvas);
    final res = BaseArcadeGame.resolution;

    // Top bar background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, res.x, 14),
      Paint()..color = Pico8Palette.darkBlue.withValues(alpha: 0.7),
    );

    _textPaint.render(canvas, 'SCORE:${game.score}', Vector2(4, 4));
    _textPaint.render(canvas, 'LVL ${game._level}', Vector2(res.x / 2 - 16, 4));

    // Lives as ship icons
    for (int i = 0; i < game.lives; i++) {
      _drawMiniShip(canvas, res.x - 10 - i * 12, 8);
    }

    // Touch zone hints when playing
    if (game._gameState == _GameState.playing) {
      final third = res.x / 3;
      final hintPaint = Paint()..color = Pico8Palette.darkBlue;
      canvas.drawRect(Rect.fromLTWH(third, res.y - 6, 1, 6), hintPaint);
      canvas.drawRect(Rect.fromLTWH(third * 2, res.y - 6, 1, 6), hintPaint);

      final zonePaint = TextPaint(
        style: TextStyle(
          color: Pico8Palette.darkBlue,
          fontSize: 5,
          fontFamily: 'PressStart2P',
        ),
      );
      zonePaint.render(canvas, '<', Vector2(third / 2 - 2, res.y - 8));
      zonePaint.render(canvas, '^', Vector2(res.x / 2 - 2, res.y - 8));
      zonePaint.render(canvas, '>', Vector2(third * 2 + third / 2 - 2, res.y - 8));
    }

    // State messages
    if (game._gameState == _GameState.waiting) {
      _textPaint.render(
        canvas,
        'ASTEROIDS',
        Vector2(res.x / 2 - 40, res.y / 2 - 20),
      );
      _smallPaint.render(
        canvas,
        'ARROWS TO MOVE',
        Vector2(res.x / 2 - 46, res.y / 2 - 6),
      );
      _smallPaint.render(
        canvas,
        'SPACE TO FIRE',
        Vector2(res.x / 2 - 30, res.y / 2 + 4),
      );
    } else if (game._gameState == _GameState.levelTransition) {
      _textPaint.render(
        canvas,
        'LEVEL ${game._level} CLEAR!',
        Vector2(res.x / 2 - 44, res.y / 2),
      );
    } else if (game._gameState == _GameState.gameOver) {
      _textPaint.render(
        canvas,
        'GAME OVER',
        Vector2(res.x / 2 - 34, res.y / 2),
      );
    }
  }

  void _drawMiniShip(Canvas canvas, double x, double y) {
    final paint = Paint()
      ..color = Pico8Palette.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(x, y - 4)
      ..lineTo(x - 3, y + 3)
      ..lineTo(x + 3, y + 3)
      ..close();
    canvas.drawPath(path, paint);
  }
}
