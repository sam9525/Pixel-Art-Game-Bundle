import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';

/// Classic Breakout arcade game with pixel-art aesthetics.
///
/// Destroy rows of colored bricks by bouncing a ball off a paddle.
/// Drag to move the paddle, tap to launch the ball. Ball speed increases
/// as bricks are destroyed. Clear all bricks to advance to the next level.
class BreakoutGame extends BaseArcadeGame with DragCallbacks, TapCallbacks {
  BreakoutGame() : super(gameId: 'breakout');

  // --- Layout constants ---
  static const double _hudHeight = 16.0;
  static const double _brickStartY = 24.0;
  static const int _brickCols = 13;
  static const int _brickRows = 8;
  static const double _brickW = 18.0;
  static const double _brickH = 8.0;
  static const double _brickGap = 1.0;
  static const double _brickOffsetX = 5.0;

  static const double _paddleW = 40.0;
  static const double _paddleH = 6.0;
  static const double _paddleY = 224.0;

  static const double _ballSize = 4.0;
  static const double _initialBallSpeed = 120.0;
  static const double _speedBumpPercent = 0.05;
  static const int _speedBumpInterval = 8;
  static const double _levelSpeedBump = 0.10;
  static const double _minVerticalRatio = 0.35;

  static const double _wallThickness = 2.0;

  // --- Row colors and points (top to bottom) ---
  static const List<Color> _rowColors = [
    Pico8Palette.red,
    Pico8Palette.red,
    Pico8Palette.orange,
    Pico8Palette.orange,
    Pico8Palette.yellow,
    Pico8Palette.yellow,
    Pico8Palette.green,
    Pico8Palette.green,
  ];

  static const List<Color> _rowHighlights = [
    Pico8Palette.pink,
    Pico8Palette.pink,
    Pico8Palette.yellow,
    Pico8Palette.yellow,
    Pico8Palette.white,
    Pico8Palette.white,
    Pico8Palette.yellow,
    Pico8Palette.yellow,
  ];

  static const List<int> _rowPoints = [7, 7, 5, 5, 3, 3, 1, 1];

  final Random _rng = Random();

  // --- Game state ---
  final List<_BrickData> _bricks = [];
  double _paddleX = 0; // paddle left-edge x
  final Vector2 _ballPos = Vector2.zero();
  final Vector2 _ballVel = Vector2.zero();
  final List<Vector2> _ballTrail = [];
  bool _alive = true;
  bool _ballAttached = true;
  double _ballSpeed = _initialBallSpeed;
  int _totalBricksDestroyed = 0;

  // Visual effect components.
  late _ScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;

    _screenFlash = _ScreenFlash(size: res.clone());

    world.addAll([
      _WallRenderer(),
      _BrickRenderer(game: this),
      _PaddleRenderer(game: this),
      _BallRenderer(game: this),
      _screenFlash,
      _HudComponent(game: this),
    ]);

    _initBricks();
    _resetPaddleAndBall();
  }

  // --- Brick initialization ---

  void _initBricks() {
    _bricks.clear();
    for (int row = 0; row < _brickRows; row++) {
      for (int col = 0; col < _brickCols; col++) {
        final x = _brickOffsetX + col * (_brickW + _brickGap);
        final y = _brickStartY + row * (_brickH + _brickGap);
        _bricks.add(_BrickData(
          rect: Rect.fromLTWH(x, y, _brickW, _brickH),
          row: row,
          alive: true,
        ));
      }
    }
  }

  void _resetPaddleAndBall() {
    final res = BaseArcadeGame.resolution;
    _paddleX = (res.x - _paddleW) / 2;
    _ballAttached = true;
    _ballVel.setZero();
    _updateAttachedBallPosition();
    _ballTrail.clear();
  }

  void _updateAttachedBallPosition() {
    _ballPos.setValues(
      _paddleX + _paddleW / 2,
      _paddleY - _ballSize / 2 - 1,
    );
  }

  void _launchBall() {
    if (!_ballAttached) return;
    _ballAttached = false;

    // Random angle: between 30 and 150 degrees upward.
    final angleRange = _rng.nextDouble() * 0.8 + 0.1; // 0.1..0.9
    final xDir = _rng.nextBool() ? 1.0 : -1.0;
    _ballVel.setValues(
      xDir * cos(angleRange) * _ballSpeed,
      -sin(angleRange) * _ballSpeed,
    );
    _ballVel.normalize();
    _ballVel.scale(_ballSpeed);
    _enforceMinVerticalSpeed();
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive) return;

    if (_ballAttached) {
      _updateAttachedBallPosition();
      return;
    }

    // Record trail position.
    _ballTrail.add(_ballPos.clone());
    if (_ballTrail.length > 3) {
      _ballTrail.removeAt(0);
    }

    // Move ball.
    _ballPos.x += _ballVel.x * dt;
    _ballPos.y += _ballVel.y * dt;

    // --- Wall collisions ---
    final res = BaseArcadeGame.resolution;

    // Left wall.
    if (_ballPos.x - _ballSize / 2 <= _wallThickness) {
      _ballPos.x = _wallThickness + _ballSize / 2;
      _ballVel.x = _ballVel.x.abs();
    }
    // Right wall.
    if (_ballPos.x + _ballSize / 2 >= res.x - _wallThickness) {
      _ballPos.x = res.x - _wallThickness - _ballSize / 2;
      _ballVel.x = -_ballVel.x.abs();
    }
    // Top wall.
    if (_ballPos.y - _ballSize / 2 <= _hudHeight) {
      _ballPos.y = _hudHeight + _ballSize / 2;
      _ballVel.y = _ballVel.y.abs();
    }

    // --- Ball fell off bottom ---
    if (_ballPos.y - _ballSize / 2 > res.y) {
      _loseLife();
      return;
    }

    // --- Paddle collision ---
    _checkPaddleCollision();

    // --- Brick collisions ---
    _checkBrickCollisions();

    // --- Level clear ---
    if (_bricks.every((b) => !b.alive)) {
      _advanceLevel();
    }
  }

  void _checkPaddleCollision() {
    final ballRect = Rect.fromCenter(
      center: Offset(_ballPos.x, _ballPos.y),
      width: _ballSize,
      height: _ballSize,
    );
    final paddleRect = Rect.fromLTWH(_paddleX, _paddleY, _paddleW, _paddleH);

    if (!ballRect.overlaps(paddleRect)) return;
    // Only bounce if ball is moving downward.
    if (_ballVel.y <= 0) return;

    // Position ball above paddle.
    _ballPos.y = _paddleY - _ballSize / 2 - 0.5;

    // Compute reflection angle based on hit position.
    // -1.0 = left edge, 0.0 = center, 1.0 = right edge.
    final paddleCenter = _paddleX + _paddleW / 2;
    final hitRatio =
        ((_ballPos.x - paddleCenter) / (_paddleW / 2)).clamp(-1.0, 1.0);

    // Map hit ratio to angle: -60 degrees to +60 degrees from vertical.
    // At center, ball goes straight up; at edges, 60 degrees outward.
    final maxAngle = pi / 3; // 60 degrees
    final angle = hitRatio * maxAngle;

    _ballVel.setValues(
      sin(angle) * _ballSpeed,
      -cos(angle) * _ballSpeed,
    );
    _enforceMinVerticalSpeed();
  }

  void _checkBrickCollisions() {
    final ballRect = Rect.fromCenter(
      center: Offset(_ballPos.x, _ballPos.y),
      width: _ballSize,
      height: _ballSize,
    );

    for (final brick in _bricks) {
      if (!brick.alive) continue;
      if (!ballRect.overlaps(brick.rect)) continue;

      // Determine which side was hit for proper reflection.
      // Calculate overlap on each axis to find the minimum penetration.
      final brickCenterX = brick.rect.center.dx;
      final brickCenterY = brick.rect.center.dy;

      final dx = _ballPos.x - brickCenterX;
      final dy = _ballPos.y - brickCenterY;

      final overlapX =
          (brick.rect.width / 2 + _ballSize / 2) - dx.abs();
      final overlapY =
          (brick.rect.height / 2 + _ballSize / 2) - dy.abs();

      if (overlapX > 0 && overlapY > 0) {
        if (overlapX < overlapY) {
          // Side hit: reflect X.
          _ballVel.x = dx > 0 ? _ballVel.x.abs() : -_ballVel.x.abs();
        } else {
          // Top/bottom hit: reflect Y.
          _ballVel.y = dy > 0 ? _ballVel.y.abs() : -_ballVel.y.abs();
        }
      }

      // Destroy brick.
      brick.alive = false;
      _totalBricksDestroyed++;
      final points = _rowPoints[brick.row];
      score += points;

      // Spawn score popup.
      world.add(_ScorePopup(
        position: Vector2(brick.rect.center.dx, brick.rect.center.dy),
        points: points,
      ));

      // Spawn brick flash particle.
      world.add(_BrickFlash(
        rect: brick.rect,
      ));

      // Speed up every N bricks.
      if (_totalBricksDestroyed % _speedBumpInterval == 0) {
        _ballSpeed *= (1.0 + _speedBumpPercent);
        _ballVel.normalize();
        _ballVel.scale(_ballSpeed);
        _enforceMinVerticalSpeed();
      }

      // Only destroy one brick per frame to avoid tunneling artifacts.
      break;
    }
  }

  void _enforceMinVerticalSpeed() {
    final speed = _ballVel.length;
    if (speed == 0) return;
    if (_ballVel.y.abs() / speed < _minVerticalRatio) {
      // Rebuild velocity with minimum vertical component.
      final sign = _ballVel.y >= 0 ? 1.0 : -1.0;
      final vy = sign * speed * _minVerticalRatio;
      final vx = _ballVel.x.sign *
          sqrt(speed * speed - vy * vy);
      _ballVel.setValues(vx, vy);
    }
  }

  void _loseLife() {
    lives -= 1;
    _screenFlash.trigger();

    if (lives <= 0) {
      _alive = false;
      onGameOver();
    } else {
      _resetPaddleAndBall();
    }
  }

  void _advanceLevel() {
    _ballSpeed *= (1.0 + _levelSpeedBump);
    _initBricks();
    _resetPaddleAndBall();
  }

  // --- Input handling ---

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final res = BaseArcadeGame.resolution;
    _paddleX += event.localDelta.x;
    _paddleX = _paddleX.clamp(
      _wallThickness,
      res.x - _wallThickness - _paddleW,
    );
    if (_ballAttached) {
      _updateAttachedBallPosition();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_ballAttached && _alive) {
      _launchBall();
    }
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _alive = true;
    _ballSpeed = _initialBallSpeed;
    _totalBricksDestroyed = 0;

    _initBricks();
    _resetPaddleAndBall();
  }

  @override
  void onGameOver() {
    _alive = false;
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Brick data record
// ---------------------------------------------------------------------------

class _BrickData {
  _BrickData({
    required this.rect,
    required this.row,
    required this.alive,
  });

  final Rect rect;
  final int row;
  bool alive;
}

// ---------------------------------------------------------------------------
// Wall renderer: left, right, and top walls
// ---------------------------------------------------------------------------

class _WallRenderer extends PositionComponent {
  final Paint _wallPaint = Paint()..color = Pico8Palette.darkGrey;
  final Paint _wallHighlight = Paint()..color = Pico8Palette.lavender;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final res = BaseArcadeGame.resolution;
    const t = BreakoutGame._wallThickness;
    final hudH = BreakoutGame._hudHeight;

    // Top wall (below HUD).
    canvas.drawRect(
      Rect.fromLTWH(0, hudH, res.x, t),
      _wallPaint,
    );
    // Top wall highlight.
    canvas.drawRect(
      Rect.fromLTWH(0, hudH, res.x, 1),
      _wallHighlight,
    );

    // Left wall.
    canvas.drawRect(
      Rect.fromLTWH(0, hudH, t, res.y - hudH),
      _wallPaint,
    );
    // Left wall highlight.
    canvas.drawRect(
      Rect.fromLTWH(0, hudH, 1, res.y - hudH),
      _wallHighlight,
    );

    // Right wall.
    canvas.drawRect(
      Rect.fromLTWH(res.x - t, hudH, t, res.y - hudH),
      _wallPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Brick renderer: draws all alive bricks with outline and highlight
// ---------------------------------------------------------------------------

class _BrickRenderer extends PositionComponent {
  _BrickRenderer({required this.game});

  final BreakoutGame game;

  final Paint _outlinePaint = Paint()..color = Pico8Palette.black;
  final Paint _fillPaint = Paint();
  final Paint _highlightPaint = Paint();

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final brick in game._bricks) {
      if (!brick.alive) continue;

      final r = brick.rect;

      // Black outline (draw slightly larger rect behind).
      _outlinePaint.color = Pico8Palette.black;
      canvas.drawRect(r, _outlinePaint);

      // Filled brick (inset by 1px for outline effect).
      _fillPaint.color = BreakoutGame._rowColors[brick.row];
      canvas.drawRect(
        Rect.fromLTWH(r.left + 1, r.top + 1, r.width - 2, r.height - 2),
        _fillPaint,
      );

      // Highlight pixel in top-left (inside the fill area).
      _highlightPaint.color = BreakoutGame._rowHighlights[brick.row];
      canvas.drawRect(
        Rect.fromLTWH(r.left + 2, r.top + 1, 1, 1),
        _highlightPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Paddle renderer
// ---------------------------------------------------------------------------

class _PaddleRenderer extends PositionComponent {
  _PaddleRenderer({required this.game});

  final BreakoutGame game;

  final Paint _paddlePaint = Paint()..color = Pico8Palette.lightGrey;
  final Paint _highlightPaint = Paint()..color = Pico8Palette.white;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final x = game._paddleX;
    const y = BreakoutGame._paddleY;
    const w = BreakoutGame._paddleW;
    const h = BreakoutGame._paddleH;

    // Main paddle body.
    canvas.drawRect(
      Rect.fromLTWH(x, y, w, h),
      _paddlePaint,
    );

    // White highlight line on top.
    canvas.drawRect(
      Rect.fromLTWH(x, y, w, 1),
      _highlightPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Ball renderer with trail
// ---------------------------------------------------------------------------

class _BallRenderer extends PositionComponent {
  _BallRenderer({required this.game});

  final BreakoutGame game;

  final Paint _ballPaint = Paint()..color = Pico8Palette.white;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    const s = BreakoutGame._ballSize;

    // Draw trail (fading older positions).
    final trail = game._ballTrail;
    for (int i = 0; i < trail.length; i++) {
      final t = (i + 1) / (trail.length + 1);
      final opacity = t * 0.4;
      final trailPaint = Paint()
        ..color = Pico8Palette.blue.withValues(alpha: opacity);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(trail[i].x, trail[i].y),
          width: s * t,
          height: s * t,
        ),
        trailPaint,
      );
    }

    // Draw ball.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(game._ballPos.x, game._ballPos.y),
        width: s,
        height: s,
      ),
      _ballPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Score popup: floating "+N" text that drifts up and fades
// ---------------------------------------------------------------------------

class _ScorePopup extends PositionComponent {
  _ScorePopup({required super.position, required this.points});

  final int points;

  static const double _lifetime = 0.6;
  static const double _driftSpeed = 35.0;

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
      fontSize: 7,
      fontFamily: 'monospace',
    );
    TextPaint(style: style).render(canvas, '+$points', Vector2.zero());
  }
}

// ---------------------------------------------------------------------------
// Brick flash: brief white rectangle at destroyed brick position
// ---------------------------------------------------------------------------

class _BrickFlash extends PositionComponent {
  _BrickFlash({required this.rect});

  final Rect rect;

  static const double _lifetime = 0.1;
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
    final opacity = (1.0 - (_elapsed / _lifetime)).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Pico8Palette.white.withValues(alpha: opacity);
    canvas.drawRect(rect, paint);
  }
}

// ---------------------------------------------------------------------------
// Screen flash on life loss
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
  static const double _duration = 0.15;
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
        paint.color = Pico8Palette.darkPurple.withValues(alpha: opacity);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// HUD: score and lives
// ---------------------------------------------------------------------------

class _HudComponent extends PositionComponent {
  _HudComponent({required this.game});

  final BreakoutGame game;

  late final TextPaint _textPaint;

  @override
  int get priority => 90;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _textPaint = TextPaint(
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

    // Dark background for HUD area.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, BaseArcadeGame.resolution.x, BreakoutGame._hudHeight),
      Paint()..color = Pico8Palette.darkBlue,
    );

    _textPaint.render(canvas, 'SCORE:${game.score}', Vector2(4, 4));
    _textPaint.render(canvas, 'LIVES:${game.lives}', Vector2(190, 4));
  }
}
