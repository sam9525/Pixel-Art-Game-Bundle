import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show FontWeight, TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

// ---------------------------------------------------------------------------
// Game state enum
// ---------------------------------------------------------------------------

enum _GameState { waiting, playing, dead }

// ---------------------------------------------------------------------------
// Obstacle data record
// ---------------------------------------------------------------------------

class _ObstacleData {
  _ObstacleData({required this.x, required this.type});
  double x;
  final _ObstacleType type;
}

enum _ObstacleType { gap, crate, spike }

// ---------------------------------------------------------------------------
// Star data for parallax background
// ---------------------------------------------------------------------------

class _StarData {
  _StarData({required this.x, required this.y, required this.layer});
  double x;
  double y;
  final int layer; // 0=far (slow), 1=mid, 2=near (fast)
}

/// Infinite Runner arcade game with pixel-art aesthetics.
///
/// Auto-running character. Tap to jump over obstacles.
/// Score increases with distance. Three lives, then game over.
class InfiniteRunnerGame extends BaseArcadeGame with TapCallbacks {
  InfiniteRunnerGame() : super(gameId: 'infinite_runner');

  // --- Layout constants ---
  static const double _playerX = 40.0;
  static const double _playerWidth = 10.0;
  static const double _playerHeight = 12.0;
  static const double _gravity = 600.0;
  static const double _jumpVelocity = -180.0;
  static const double _groundHeight = 20.0;
  static const double _baseScrollSpeed = 80.0;
  static const double _maxScrollSpeed = 200.0;
  static const double _speedIncrement = 0.5; // per point scored
  static const double _obstacleSpawnMinInterval = 1.2;
  static const double _obstacleSpawnMaxInterval = 2.5;
  static const double _gapWidth = 18.0;
  static const double _crateWidth = 10.0;
  static const double _crateHeight = 10.0;
  static const double _spikeWidth = 12.0;
  static const double _spikeHeight = 8.0;
  static const double _deathPauseDuration = 1.0;

  final Random _rng = Random();

  // --- Game state ---
  double _playerY = 0;
  double _playerVelocity = 0;
  final List<_ObstacleData> _obstacles = [];
  _GameState _gameState = _GameState.waiting;
  double _obstacleSpawnTimer = 0;
  double _groundScrollX = 0;
  double _deathTimer = 0;
  double _waitTimer = 0;
  double _currentSpeed = _baseScrollSpeed;
  double _scoreTimer = 0;
  bool _isOnGround = true;

  final List<_StarData> _stars = [];

  double get groundY => BaseArcadeGame.resolution.y - _groundHeight;

  late SharedScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.darkBlue;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = SharedScreenFlash(size: res.clone());

    _initStars();

    world.addAll([
      _BackgroundRenderer(game: this),
      _GroundRenderer(game: this),
      _ObstacleRenderer(game: this),
      _PlayerRenderer(game: this),
      _screenFlash,
      _HudComponent(game: this),
    ]);

    _resetState();
  }

  void _initStars() {
    _stars.clear();
    final res = BaseArcadeGame.resolution;
    // Far stars (slow)
    for (int i = 0; i < 15; i++) {
      _stars.add(_StarData(
        x: _rng.nextDouble() * res.x,
        y: _rng.nextDouble() * (groundY - 40),
        layer: 0,
      ));
    }
    // Mid stars
    for (int i = 0; i < 10; i++) {
      _stars.add(_StarData(
        x: _rng.nextDouble() * res.x,
        y: _rng.nextDouble() * (groundY - 40),
        layer: 1,
      ));
    }
    // Near stars (faster)
    for (int i = 0; i < 8; i++) {
      _stars.add(_StarData(
        x: _rng.nextDouble() * res.x,
        y: _rng.nextDouble() * (groundY - 40),
        layer: 2,
      ));
    }
  }

  void _resetState() {
    _playerY = groundY - _playerHeight;
    _playerVelocity = 0;
    _obstacles.clear();
    _gameState = _GameState.waiting;
    _obstacleSpawnTimer = 0;
    _groundScrollX = 0;
    _deathTimer = 0;
    _waitTimer = 0;
    _currentSpeed = _baseScrollSpeed;
    _scoreTimer = 0;
    _isOnGround = true;
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);

    switch (_gameState) {
      case _GameState.waiting:
        _updateWaiting(dt);
        break;
      case _GameState.playing:
        _updatePlaying(dt);
        break;
      case _GameState.dead:
        _updateDead(dt);
        break;
    }
  }

  void _updateWaiting(double dt) {
    _waitTimer += dt;
    // Bob the player gently.
    _playerY = (groundY - _playerHeight) +
        sin(_waitTimer * 3.0 * 2 * pi) * 2.0;

    // Scroll ground and stars for visual life.
    _groundScrollX = (_groundScrollX + _baseScrollSpeed * dt) % 16.0;
    _scrollStars(dt, _baseScrollSpeed);
  }

  void _updatePlaying(double dt) {
    // Player physics (gravity).
    _playerVelocity += _gravity * dt;
    _playerY += _playerVelocity * dt;

    // Check if landed on ground.
    if (_playerY + _playerHeight >= groundY) {
      _playerY = groundY - _playerHeight;
      _playerVelocity = 0;
      _isOnGround = true;
    }

    // Scroll ground.
    _groundScrollX = (_groundScrollX + _currentSpeed * dt) % 16.0;

    // Scroll stars with parallax.
    _scrollStars(dt, _currentSpeed);

    // Update score (distance).
    _scoreTimer += dt;
    if (_scoreTimer >= 0.1) {
      _scoreTimer -= 0.1;
      score += 1;
      // Increase speed every few points.
      if (score % 10 == 0 && _currentSpeed < _maxScrollSpeed) {
        _currentSpeed += _speedIncrement * 10;
      }
    }

    // Obstacle spawning.
    _obstacleSpawnTimer += dt;
    final spawnInterval = _obstacleSpawnMinInterval +
        _rng.nextDouble() * (_obstacleSpawnMaxInterval - _obstacleSpawnMinInterval);
    // Speed up spawning as score increases.
    final adjustedInterval = spawnInterval * (_baseScrollSpeed / _currentSpeed);
    if (_obstacleSpawnTimer >= adjustedInterval) {
      _obstacleSpawnTimer = 0;
      _spawnObstacle();
    }

    // Move obstacles.
    for (final obs in _obstacles) {
      obs.x -= _currentSpeed * dt;
    }

    // Remove off-screen obstacles.
    _obstacles.removeWhere((obs) => obs.x < -_spikeWidth);

    // Collision detection.
    _checkCollisions();
  }

  void _updateDead(double dt) {
    // Player falls during death.
    _playerVelocity += _gravity * dt;
    _playerY += _playerVelocity * dt;

    // Clamp to ground.
    if (_playerY + _playerHeight >= groundY) {
      _playerY = groundY - _playerHeight;
      _playerVelocity = 0;
    }

    _deathTimer += dt;
    if (_deathTimer >= _deathPauseDuration) {
      if (lives <= 0) {
        onGameOver();
      } else {
        // Respawn.
        _obstacles.clear();
        _obstacleSpawnTimer = 0;
        _playerY = groundY - _playerHeight;
        _playerVelocity = 0;
        _currentSpeed = _baseScrollSpeed;
        _scoreTimer = 0;
        _isOnGround = true;
        _gameState = _GameState.waiting;
        _waitTimer = 0;
      }
    }
  }

  void _scrollStars(double dt, double speed) {
    final res = BaseArcadeGame.resolution;
    final speeds = [speed * 0.2, speed * 0.4, speed * 0.6];
    for (final star in _stars) {
      star.x -= speeds[star.layer] * dt;
      if (star.x < 0) {
        star.x = res.x + _rng.nextDouble() * 20;
        star.y = _rng.nextDouble() * (groundY - 30);
      }
    }
  }

  void _spawnObstacle() {
    final res = BaseArcadeGame.resolution;
    final typeIndex = _rng.nextInt(3);
    final type = _ObstacleType.values[typeIndex];
    _obstacles.add(_ObstacleData(x: res.x + 10, type: type));
  }

  void _checkCollisions() {
    final playerRect = Rect.fromLTWH(
      _playerX,
      _playerY,
      _playerWidth,
      _playerHeight,
    );

    // Player vs ground (check if in a gap).
    bool overGap = false;
    for (final obs in _obstacles) {
      if (obs.type == _ObstacleType.gap) {
        final gapLeft = obs.x;
        final gapRight = obs.x + _gapWidth;
        if (_playerX + _playerWidth > gapLeft && _playerX < gapRight) {
          overGap = true;
          break;
        }
      }
    }

    // Check if player fell into gap.
    if (overGap && _playerY + _playerHeight >= groundY - 2) {
      _onHit();
      return;
    }

    // Player vs obstacles.
    for (final obs in _obstacles) {
      if (obs.type == _ObstacleType.gap) continue;
      final obsRect = obs.type == _ObstacleType.crate
          ? Rect.fromLTWH(
              obs.x,
              groundY - _crateHeight,
              _crateWidth,
              _crateHeight,
            )
          : Rect.fromLTWH(
              obs.x,
              groundY - _spikeHeight,
              _spikeWidth,
              _spikeHeight,
            );
      if (playerRect.overlaps(obsRect)) {
        _onHit();
        return;
      }
    }
  }

  void _onHit() {
    lives -= 1;
    _screenFlash.trigger();
    _gameState = _GameState.dead;
    _deathTimer = 0;
    _playerVelocity = -80; // Small upward bump on death.
  }

  // --- Input handling ---

  @override
  void onTapDown(TapDownEvent event) {
    switch (_gameState) {
      case _GameState.waiting:
        _gameState = _GameState.playing;
        if (_isOnGround) {
          _playerVelocity = _jumpVelocity;
          _isOnGround = false;
        }
        break;
      case _GameState.playing:
        if (_isOnGround) {
          _playerVelocity = _jumpVelocity;
          _isOnGround = false;
        }
        break;
      case _GameState.dead:
        // Ignore taps while dying.
        break;
    }
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _resetState();
  }

  @override
  void onGameOver() {
    _gameState = _GameState.dead;
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Background renderer: parallax stars
// ---------------------------------------------------------------------------

class _BackgroundRenderer extends PositionComponent {
  _BackgroundRenderer({required this.game});

  final InfiniteRunnerGame game;

  final Paint _starFar = Paint()..color = Pico8Palette.lightGrey;
  final Paint _starMid = Paint()..color = Pico8Palette.white;
  final Paint _starNear = Paint()..color = Pico8Palette.white;

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final star in game._stars) {
      final paint = switch (star.layer) {
        0 => _starFar,
        1 => _starMid,
        _ => _starNear,
      };
      final size = switch (star.layer) {
        0 => 1.0,
        1 => 1.0,
        _ => 2.0,
      };
      canvas.drawRect(
        Rect.fromLTWH(star.x, star.y, size, size),
        paint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ground renderer: scrolling brown ground with grass
// ---------------------------------------------------------------------------

class _GroundRenderer extends PositionComponent {
  _GroundRenderer({required this.game});

  final InfiniteRunnerGame game;

  final Paint _groundPaint = Paint()..color = Pico8Palette.brown;
  final Paint _grassPaint = Paint()..color = Pico8Palette.darkGreen;
  final Paint _grassHighlight = Paint()..color = Pico8Palette.green;
  final Paint _groundDetail = Paint()..color = Pico8Palette.darkGrey;
  final Paint _gapPaint = Paint()..color = Pico8Palette.black;

  @override
  int get priority => 10;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final res = BaseArcadeGame.resolution;
    final gy = game.groundY;

    // First draw solid ground, then draw gaps on top.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, res.x, InfiniteRunnerGame._groundHeight),
      _groundPaint,
    );

    // Grass top.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, res.x, 2),
      _grassPaint,
    );

    // Scrolling ground detail pattern.
    final scrollOffset = game._groundScrollX;

    // Draw gaps as black rectangles.
    for (final obs in game._obstacles) {
      if (obs.type == _ObstacleType.gap) {
        canvas.drawRect(
          Rect.fromLTWH(
            obs.x,
            gy,
            InfiniteRunnerGame._gapWidth,
            InfiniteRunnerGame._groundHeight,
          ),
          _gapPaint,
        );
      }
    }

    // Grass tufts and ground texture.
    for (double x = -scrollOffset; x < res.x; x += 16) {
      // Small grass tufts.
      canvas.drawRect(
        Rect.fromLTWH(x, gy - 1, 2, 1),
        _grassHighlight,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 6, gy - 1, 1, 1),
        _grassHighlight,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 10, gy - 1, 2, 1),
        _grassHighlight,
      );

      // Ground texture dots.
      canvas.drawRect(
        Rect.fromLTWH(x + 3, gy + 6, 1, 1),
        _groundDetail,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 11, gy + 12, 1, 1),
        _groundDetail,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Obstacle renderer: crates and spikes
// ---------------------------------------------------------------------------

class _ObstacleRenderer extends PositionComponent {
  _ObstacleRenderer({required this.game});

  final InfiniteRunnerGame game;

  final Paint _cratePaint = Paint()..color = Pico8Palette.brown;
  final Paint _crateHighlight = Paint()..color = Pico8Palette.lightPeach;
  final Paint _crateShadow = Paint()..color = Pico8Palette.darkGrey;
  final Paint _spikePaint = Paint()..color = Pico8Palette.darkGrey;
  final Paint _spikeHighlight = Paint()..color = Pico8Palette.lightGrey;

  @override
  int get priority => 15;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final gy = game.groundY;

    for (final obs in game._obstacles) {
      switch (obs.type) {
        case _ObstacleType.gap:
          // Gaps are drawn by ground renderer.
          continue;
        case _ObstacleType.crate:
          final cx = obs.x;
          final cw = InfiniteRunnerGame._crateWidth;
          final ch = InfiniteRunnerGame._crateHeight;
          // Main crate body.
          canvas.drawRect(
            Rect.fromLTWH(cx, gy - ch, cw, ch),
            _cratePaint,
          );
          // Highlight on top-left.
          canvas.drawRect(
            Rect.fromLTWH(cx, gy - ch, cw, 1),
            _crateHighlight,
          );
          canvas.drawRect(
            Rect.fromLTWH(cx, gy - ch, 1, ch),
            _crateHighlight,
          );
          // Shadow on bottom-right.
          canvas.drawRect(
            Rect.fromLTWH(cx + cw - 1, gy - ch, 1, ch),
            _crateShadow,
          );
          canvas.drawRect(
            Rect.fromLTWH(cx, gy - 1, cw, 1),
            _crateShadow,
          );
          // Cross pattern on crate.
          canvas.drawRect(
            Rect.fromLTWH(cx + cw / 2 - 1, gy - ch + 2, 2, ch - 4),
            _crateShadow,
          );
          canvas.drawRect(
            Rect.fromLTWH(cx + 2, gy - ch / 2 - 1, cw - 4, 2),
            _crateShadow,
          );
          break;
        case _ObstacleType.spike:
          final sx = obs.x;
          final sw = InfiniteRunnerGame._spikeWidth;
          final sh = InfiniteRunnerGame._spikeHeight;
          // Draw two triangular spikes.
          for (int i = 0; i < 2; i++) {
            final spikeX = sx + i * (sw / 2);
            // Spike as a triangle using rectangles.
            canvas.drawRect(
              Rect.fromLTWH(spikeX + 2, gy - sh + 2, sw / 2 - 4, sh - 2),
              _spikePaint,
            );
            canvas.drawRect(
              Rect.fromLTWH(spikeX + 1, gy - sh + 4, sw / 2 - 2, sh - 4),
              _spikePaint,
            );
            canvas.drawRect(
              Rect.fromLTWH(spikeX + 3, gy - sh, sw / 2 - 6, 2),
              _spikeHighlight,
            );
          }
          break;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Player renderer: pixel art running character
// ---------------------------------------------------------------------------

class _PlayerRenderer extends PositionComponent {
  _PlayerRenderer({required this.game});

  final InfiniteRunnerGame game;

  final Paint _bodyPaint = Paint()..color = Pico8Palette.orange;
  final Paint _headPaint = Paint()..color = Pico8Palette.lightPeach;
  final Paint _eyePaint = Paint()..color = Pico8Palette.black;
  final Paint _legPaint = Paint()..color = Pico8Palette.darkGrey;
  final Paint _armPaint = Paint()..color = Pico8Palette.orange;

  double _runCycle = 0;

  @override
  int get priority => 30;

  @override
  void update(double dt) {
    super.update(dt);
    if (game._gameState == _GameState.playing) {
      _runCycle += dt * 10;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final px = InfiniteRunnerGame._playerX;
    final py = game._playerY;
    final pw = InfiniteRunnerGame._playerWidth;
    final ph = InfiniteRunnerGame._playerHeight;

    // Running animation frame.
    final legOffset = game._gameState == _GameState.playing
        ? (sin(_runCycle) * 2).abs()
        : 0.0;

    // Head (top portion).
    canvas.drawRect(
      Rect.fromLTWH(px + 2, py, pw - 4, 5),
      _headPaint,
    );
    // Eye.
    canvas.drawRect(
      Rect.fromLTWH(px + pw - 4, py + 1, 2, 2),
      _eyePaint,
    );

    // Body.
    canvas.drawRect(
      Rect.fromLTWH(px + 1, py + 5, pw - 2, 4),
      _bodyPaint,
    );

    // Arms (alternating).
    final armY = py + 6;
    if (game._gameState == _GameState.playing) {
      final armSwing = sin(_runCycle) * 2;
      canvas.drawRect(
        Rect.fromLTWH(px - 1, armY + armSwing.floor(), 2, 3),
        _armPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(px + pw - 1, armY - armSwing.floor(), 2, 3),
        _armPaint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(px - 1, armY, 2, 3),
        _armPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(px + pw - 1, armY, 2, 3),
        _armPaint,
      );
    }

    // Legs (running animation).
    if (game._gameState == _GameState.playing) {
      // Left leg.
      canvas.drawRect(
        Rect.fromLTWH(px + 2, py + ph - 4 + legOffset.floor(), 2, (4 - legOffset.floor()).toDouble()),
        _legPaint,
      );
      // Right leg.
      canvas.drawRect(
        Rect.fromLTWH(px + pw - 4, py + ph - 4 + (2 - legOffset).floor(), 2, (4 - (2 - legOffset).floor()).toDouble()),
        _legPaint,
      );
    } else {
      // Standing.
      canvas.drawRect(
        Rect.fromLTWH(px + 2, py + ph - 4, 2, 4),
        _legPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(px + pw - 4, py + ph - 4, 2, 4),
        _legPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// HUD component: score display and "TAP TO START" message
// ---------------------------------------------------------------------------

class _HudComponent extends PositionComponent {
  _HudComponent({required this.game});

  final InfiniteRunnerGame game;

  late final TextPaint _scorePaint;
  late final TextPaint _startPaint;

  @override
  int get priority => 80;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _scorePaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 16,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
    _startPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 8,
        fontFamily: 'monospace',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final res = BaseArcadeGame.resolution;

    if (game._gameState == _GameState.waiting) {
      // "TAP TO START" centered.
      _startPaint.render(
        canvas,
        'TAP TO JUMP',
        Vector2(res.x / 2 - 30, res.y / 2 + 20),
      );
    }

    if (game._gameState == _GameState.playing ||
        game._gameState == _GameState.dead) {
      // Large centered score at top.
      final scoreText = '${game.score}';
      final textWidth = scoreText.length * 10.0;
      _scorePaint.render(
        canvas,
        scoreText,
        Vector2((res.x - textWidth) / 2, 12),
      );
    }

    if (game._gameState == _GameState.dead && game.lives > 0) {
      _startPaint.render(
        canvas,
        'TAP TO CONTINUE',
        Vector2(res.x / 2 - 36, res.y / 2 + 20),
      );
    }
  }
}
