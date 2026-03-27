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
// Pipe data record
// ---------------------------------------------------------------------------

class _PipeData {
  _PipeData({required this.x, required this.gapCenterY})
      : scored = false;

  double x;
  final double gapCenterY;
  bool scored;
}

// ---------------------------------------------------------------------------
// Cloud data record
// ---------------------------------------------------------------------------

class _CloudData {
  _CloudData({required this.x, required this.y, required this.width});

  double x;
  final double y;
  final double width;
}

/// Flappy Bird arcade game with pixel-art aesthetics.
///
/// Tap to flap. Navigate the bird through gaps in scrolling pipes.
/// Each pipe pair cleared scores one point. Three lives, then game over.
class FlappyGame extends BaseArcadeGame with TapCallbacks {
  FlappyGame() : super(gameId: 'flappy');

  // --- Layout constants ---
  static const double _birdX = 60.0;
  static const double _birdSize = 8.0;
  static const double _gravity = 400.0;
  static const double _flapImpulse = -140.0;
  static const double _pipeWidth = 26.0;
  static const double _pipeCapWidth = 30.0;
  static const double _pipeCapHeight = 6.0;
  static const double _gapHeight = 50.0;
  static const double _pipeSpeed = 80.0;
  static const double _groundHeight = 24.0;
  static const double _grassHeight = 2.0;
  static const double _cloudSpeed = 20.0;
  static const double _pipeSpawnInterval = 2.0;
  static const double _minGapY = 40.0;
  static const double _maxGapY = 170.0;
  static const double _deathPauseDuration = 1.0;
  static const double _bobAmplitude = 4.0;
  static const double _bobFrequency = 2.5;
  static const double _wingInterval = 0.15;
  static const double _maxTiltUp = -30.0 * pi / 180.0;
  static const double _maxTiltDown = 70.0 * pi / 180.0;

  final Random _rng = Random();

  // --- Game state ---
  double _birdY = 0;
  double _birdVelocity = 0;
  final List<_PipeData> _pipes = [];
  _GameState _gameState = _GameState.waiting;
  double _pipeSpawnTimer = 0;
  double _groundScrollX = 0;
  double _wingTimer = 0;
  bool _wingUp = true;
  double _deathTimer = 0;
  double _waitTimer = 0;

  final List<_CloudData> _clouds = [];

  double get groundY => BaseArcadeGame.resolution.y - _groundHeight;

  late SharedScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.darkBlue;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = SharedScreenFlash(size: res.clone());

    _initClouds();

    world.addAll([
      _BackgroundRenderer(game: this),
      _PipeRenderer(game: this),
      _GroundRenderer(game: this),
      _BirdRenderer(game: this),
      _screenFlash,
      _HudComponent(game: this),
    ]);

    _resetState();
  }

  void _initClouds() {
    _clouds.clear();
    // Create several clouds at fixed positions.
    _clouds.addAll([
      _CloudData(x: 30, y: 25, width: 24),
      _CloudData(x: 110, y: 50, width: 18),
      _CloudData(x: 200, y: 15, width: 28),
      _CloudData(x: 160, y: 65, width: 16),
      _CloudData(x: 60, y: 75, width: 20),
      _CloudData(x: 240, y: 40, width: 22),
    ]);
  }

  void _resetState() {
    final res = BaseArcadeGame.resolution;
    _birdY = res.y / 2 - _birdSize / 2;
    _birdVelocity = 0;
    _pipes.clear();
    _gameState = _GameState.waiting;
    _pipeSpawnTimer = 0;
    _groundScrollX = 0;
    _wingTimer = 0;
    _wingUp = true;
    _deathTimer = 0;
    _waitTimer = 0;
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);

    // Wing animation runs in all states (except dead).
    if (_gameState != _GameState.dead) {
      _wingTimer += dt;
      if (_wingTimer >= _wingInterval) {
        _wingTimer -= _wingInterval;
        _wingUp = !_wingUp;
      }
    }

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
    // Bob the bird gently.
    final res = BaseArcadeGame.resolution;
    _birdY = (res.y / 2 - _birdSize / 2) +
        sin(_waitTimer * _bobFrequency * 2 * pi) * _bobAmplitude;

    // Scroll ground and clouds for visual life.
    _groundScrollX = (_groundScrollX + _pipeSpeed * dt) % 16.0;
    _scrollClouds(dt);
  }

  void _updatePlaying(double dt) {
    // Bird physics.
    _birdVelocity += _gravity * dt;
    _birdY += _birdVelocity * dt;

    // Scroll ground.
    _groundScrollX = (_groundScrollX + _pipeSpeed * dt) % 16.0;

    // Scroll clouds.
    _scrollClouds(dt);

    // Pipe spawning.
    _pipeSpawnTimer += dt;
    if (_pipeSpawnTimer >= _pipeSpawnInterval) {
      _pipeSpawnTimer -= _pipeSpawnInterval;
      _spawnPipe();
    }

    // Move pipes.
    for (final pipe in _pipes) {
      pipe.x -= _pipeSpeed * dt;
    }

    // Remove off-screen pipes.
    _pipes.removeWhere((p) => p.x < -_pipeCapWidth);

    // Score check.
    for (final pipe in _pipes) {
      if (!pipe.scored && pipe.x + _pipeWidth / 2 < _birdX) {
        pipe.scored = true;
        score += 1;
        world.add(SharedScorePopup(
          position: Vector2(pipe.x + _pipeWidth / 2, pipe.gapCenterY - 30),
        ));
      }
    }

    // Collision detection.
    _checkCollisions();
  }

  void _updateDead(double dt) {
    // Bird falls during death.
    _birdVelocity += _gravity * dt;
    _birdY += _birdVelocity * dt;

    // Clamp to ground.
    if (_birdY + _birdSize >= groundY) {
      _birdY = groundY - _birdSize;
      _birdVelocity = 0;
    }

    _deathTimer += dt;
    if (_deathTimer >= _deathPauseDuration) {
      if (lives <= 0) {
        onGameOver();
      } else {
        // Respawn.
        _pipes.clear();
        _pipeSpawnTimer = 0;
        final res = BaseArcadeGame.resolution;
        _birdY = res.y / 2 - _birdSize / 2;
        _birdVelocity = 0;
        _gameState = _GameState.waiting;
        _waitTimer = 0;
      }
    }
  }

  void _scrollClouds(double dt) {
    final res = BaseArcadeGame.resolution;
    for (final cloud in _clouds) {
      cloud.x -= _cloudSpeed * dt;
      if (cloud.x + cloud.width < 0) {
        cloud.x = res.x + _rng.nextDouble() * 40;
      }
    }
  }

  void _spawnPipe() {
    final res = BaseArcadeGame.resolution;
    final gapCenterY =
        _minGapY + _rng.nextDouble() * (_maxGapY - _minGapY);
    _pipes.add(_PipeData(x: res.x, gapCenterY: gapCenterY));
  }

  void _checkCollisions() {
    final birdRect = Rect.fromLTWH(_birdX - _birdSize / 2,
        _birdY, _birdSize, _birdSize);

    // Bird vs ceiling.
    if (_birdY <= 0) {
      _onHit();
      return;
    }

    // Bird vs ground.
    if (_birdY + _birdSize >= groundY) {
      _onHit();
      return;
    }

    // Bird vs pipes.
    for (final pipe in _pipes) {
      // Top pipe body.
      final topGapEdge = pipe.gapCenterY - _gapHeight / 2;
      final topPipeRect = Rect.fromLTWH(pipe.x, 0, _pipeWidth, topGapEdge);

      // Top pipe cap.
      final topCapX = pipe.x - (_pipeCapWidth - _pipeWidth) / 2;
      final topCapRect = Rect.fromLTWH(
          topCapX, topGapEdge - _pipeCapHeight, _pipeCapWidth, _pipeCapHeight);

      // Bottom pipe body.
      final bottomGapEdge = pipe.gapCenterY + _gapHeight / 2;
      final bottomPipeRect =
          Rect.fromLTWH(pipe.x, bottomGapEdge, _pipeWidth, groundY - bottomGapEdge);

      // Bottom pipe cap.
      final bottomCapX = pipe.x - (_pipeCapWidth - _pipeWidth) / 2;
      final bottomCapRect = Rect.fromLTWH(
          bottomCapX, bottomGapEdge, _pipeCapWidth, _pipeCapHeight);

      if (birdRect.overlaps(topPipeRect) ||
          birdRect.overlaps(topCapRect) ||
          birdRect.overlaps(bottomPipeRect) ||
          birdRect.overlaps(bottomCapRect)) {
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
    _birdVelocity = -80; // Small upward bump on death.
  }

  // --- Input handling ---

  @override
  void onTapDown(TapDownEvent event) {
    switch (_gameState) {
      case _GameState.waiting:
        _gameState = _GameState.playing;
        _birdVelocity = _flapImpulse;
        break;
      case _GameState.playing:
        _birdVelocity = _flapImpulse;
        break;
      case _GameState.dead:
        // Ignore taps while dying.
        break;
    }
  }

  // --- Bird tilt angle ---

  double get birdAngle {
    // Map velocity to angle: negative velocity = tilt up, positive = tilt down.
    final t = (_birdVelocity / 200.0).clamp(-1.0, 1.0);
    if (t < 0) {
      return t * -_maxTiltUp; // tilt up (negative angle)
    } else {
      return t * _maxTiltDown; // tilt down (positive angle)
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
// Background renderer: sky + slow-scrolling clouds
// ---------------------------------------------------------------------------

class _BackgroundRenderer extends PositionComponent {
  _BackgroundRenderer({required this.game});

  final FlappyGame game;

  final Paint _cloudPaint = Paint()..color = Pico8Palette.lightGrey;
  final Paint _cloudHighlight = Paint()..color = Pico8Palette.white;

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Sky is handled by backgroundColor, draw clouds.
    for (final cloud in game._clouds) {
      // Main cloud body: a small pixel blob.
      final cx = cloud.x;
      final cy = cloud.y;
      final w = cloud.width;

      // Draw cloud as overlapping rectangles for pixel art feel.
      canvas.drawRect(
        Rect.fromLTWH(cx + 2, cy, w - 4, 6),
        _cloudPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(cx, cy + 2, w, 4),
        _cloudPaint,
      );
      // Highlight on top.
      canvas.drawRect(
        Rect.fromLTWH(cx + 4, cy, w - 8, 1),
        _cloudHighlight,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Pipe renderer: draws all active pipes from game state
// ---------------------------------------------------------------------------

class _PipeRenderer extends PositionComponent {
  _PipeRenderer({required this.game});

  final FlappyGame game;

  final Paint _pipePaint = Paint()..color = Pico8Palette.darkGreen;
  final Paint _pipeHighlight = Paint()..color = Pico8Palette.green;
  final Paint _capBorder = Paint()..color = Pico8Palette.green;

  @override
  int get priority => 10;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final pipe in game._pipes) {
      final topGapEdge = pipe.gapCenterY - FlappyGame._gapHeight / 2;
      final bottomGapEdge = pipe.gapCenterY + FlappyGame._gapHeight / 2;
      final pipeW = FlappyGame._pipeWidth;
      final capW = FlappyGame._pipeCapWidth;
      final capH = FlappyGame._pipeCapHeight;
      final capOffsetX = (capW - pipeW) / 2;

      // --- Top pipe ---
      // Body.
      canvas.drawRect(
        Rect.fromLTWH(pipe.x, 0, pipeW, topGapEdge - capH),
        _pipePaint,
      );
      // Highlight stripe on bottom edge of top pipe body (facing gap).
      canvas.drawRect(
        Rect.fromLTWH(pipe.x, 0, 2, topGapEdge - capH),
        _pipeHighlight,
      );

      // Cap.
      final topCapX = pipe.x - capOffsetX;
      final topCapY = topGapEdge - capH;
      canvas.drawRect(
        Rect.fromLTWH(topCapX, topCapY, capW, capH),
        _pipePaint,
      );
      // Cap border (1px green border).
      canvas.drawRect(
        Rect.fromLTWH(topCapX, topCapY, capW, 1),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(topCapX, topCapY, 1, capH),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(topCapX + capW - 1, topCapY, 1, capH),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(topCapX, topCapY + capH - 1, capW, 1),
        _capBorder,
      );

      // --- Bottom pipe ---
      // Body.
      canvas.drawRect(
        Rect.fromLTWH(pipe.x, bottomGapEdge + capH, pipeW,
            game.groundY - bottomGapEdge - capH),
        _pipePaint,
      );
      // Highlight stripe on top edge of bottom pipe body (facing gap).
      canvas.drawRect(
        Rect.fromLTWH(pipe.x, bottomGapEdge + capH, 2,
            game.groundY - bottomGapEdge - capH),
        _pipeHighlight,
      );

      // Cap.
      final bottomCapX = pipe.x - capOffsetX;
      final bottomCapY = bottomGapEdge;
      canvas.drawRect(
        Rect.fromLTWH(bottomCapX, bottomCapY, capW, capH),
        _pipePaint,
      );
      // Cap border.
      canvas.drawRect(
        Rect.fromLTWH(bottomCapX, bottomCapY, capW, 1),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(bottomCapX, bottomCapY, 1, capH),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(bottomCapX + capW - 1, bottomCapY, 1, capH),
        _capBorder,
      );
      canvas.drawRect(
        Rect.fromLTWH(bottomCapX, bottomCapY + capH - 1, capW, 1),
        _capBorder,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ground renderer: scrolling brown ground with green grass top
// ---------------------------------------------------------------------------

class _GroundRenderer extends PositionComponent {
  _GroundRenderer({required this.game});

  final FlappyGame game;

  final Paint _groundPaint = Paint()..color = Pico8Palette.brown;
  final Paint _grassPaint = Paint()..color = Pico8Palette.darkGreen;
  final Paint _grassHighlight = Paint()..color = Pico8Palette.green;
  final Paint _groundDetail = Paint()..color = Pico8Palette.darkGrey;

  @override
  int get priority => 20;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final res = BaseArcadeGame.resolution;
    final gy = game.groundY;

    // Brown ground base.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, res.x, FlappyGame._groundHeight),
      _groundPaint,
    );

    // Dark green grass strip on top.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, res.x, FlappyGame._grassHeight),
      _grassPaint,
    );

    // Scrolling grass detail pattern (alternating lighter pixels).
    final scrollOffset = game._groundScrollX;
    for (double x = -scrollOffset; x < res.x; x += 16) {
      // Small grass tufts every 16px.
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
// Bird renderer: pixel art bird with rotation and wing animation
// ---------------------------------------------------------------------------

class _BirdRenderer extends PositionComponent {
  _BirdRenderer({required this.game});

  final FlappyGame game;

  final Paint _bodyPaint = Paint()..color = Pico8Palette.yellow;
  final Paint _beakPaint = Paint()..color = Pico8Palette.orange;
  final Paint _eyeWhite = Paint()..color = Pico8Palette.white;
  final Paint _eyePupil = Paint()..color = Pico8Palette.black;
  final Paint _wingPaint = Paint()..color = Pico8Palette.orange;

  @override
  int get priority => 30;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final bx = FlappyGame._birdX;
    final by = game._birdY;
    final angle = game._gameState == _GameState.waiting ? 0.0 : game.birdAngle;

    canvas.save();
    // Translate to bird center, rotate, translate back.
    canvas.translate(bx, by + FlappyGame._birdSize / 2);
    canvas.rotate(angle);
    canvas.translate(-FlappyGame._birdSize / 2, -FlappyGame._birdSize / 2);

    // Body: 8x8 yellow block (slightly shaped).
    // Main body (rows 1-6, cols 0-5).
    canvas.drawRect(Rect.fromLTWH(1, 0, 5, 1), _bodyPaint); // Top row
    canvas.drawRect(Rect.fromLTWH(0, 1, 7, 1), _bodyPaint); // Row 2
    canvas.drawRect(Rect.fromLTWH(0, 2, 7, 1), _bodyPaint); // Row 3
    canvas.drawRect(Rect.fromLTWH(0, 3, 7, 1), _bodyPaint); // Row 4
    canvas.drawRect(Rect.fromLTWH(0, 4, 7, 1), _bodyPaint); // Row 5
    canvas.drawRect(Rect.fromLTWH(1, 5, 6, 1), _bodyPaint); // Row 6
    canvas.drawRect(Rect.fromLTWH(1, 6, 5, 1), _bodyPaint); // Row 7
    canvas.drawRect(Rect.fromLTWH(2, 7, 3, 1), _bodyPaint); // Bottom row

    // Beak: orange triangle on right side (2px wide at rows 3-4).
    canvas.drawRect(Rect.fromLTWH(7, 2, 1, 1), _beakPaint);
    canvas.drawRect(Rect.fromLTWH(7, 3, 2, 1), _beakPaint);
    canvas.drawRect(Rect.fromLTWH(7, 4, 1, 1), _beakPaint);

    // Eye: white background at (5,1), pupil at (5,2) or (6,1).
    canvas.drawRect(Rect.fromLTWH(5, 1, 2, 2), _eyeWhite);
    canvas.drawRect(Rect.fromLTWH(6, 1, 1, 1), _eyePupil);

    // Wing: alternates position based on _wingUp.
    if (game._wingUp) {
      // Wing up: at row 2-3, cols 1-3.
      canvas.drawRect(Rect.fromLTWH(1, 2, 3, 1), _wingPaint);
      canvas.drawRect(Rect.fromLTWH(0, 3, 3, 1), _wingPaint);
    } else {
      // Wing down: at row 4-5, cols 1-3.
      canvas.drawRect(Rect.fromLTWH(1, 4, 3, 1), _wingPaint);
      canvas.drawRect(Rect.fromLTWH(0, 5, 3, 1), _wingPaint);
    }

    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// HUD component: score display and "TAP TO START" message
// ---------------------------------------------------------------------------

class _HudComponent extends PositionComponent {
  _HudComponent({required this.game});

  final FlappyGame game;

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
      final text = 'TAP TO START';
      _startPaint.render(
        canvas,
        text,
        Vector2(res.x / 2 - 36, res.y / 2 + 30),
      );
    }

    if (game._gameState == _GameState.playing ||
        game._gameState == _GameState.dead) {
      // Large centered score at top.
      final scoreText = '${game.score}';
      // Approximate centering: each char ~10px wide at size 16.
      final textWidth = scoreText.length * 10.0;
      _scorePaint.render(
        canvas,
        scoreText,
        Vector2((res.x - textWidth) / 2, 12),
      );
    }
  }
}

