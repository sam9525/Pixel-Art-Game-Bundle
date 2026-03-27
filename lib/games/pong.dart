import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

/// Classic Pong arcade game with pixel-art aesthetics.
///
/// Player paddle at the bottom, AI paddle at the top.
/// Ball bounces off walls and paddles, speeding up after each hit.
class PongGame extends BaseArcadeGame with DragCallbacks {
  PongGame() : super(gameId: 'pong');

  static const double _paddleWidth = 32.0;
  static const double _paddleHeight = 4.0;
  static const double _paddleMargin = 12.0;
  static const double _ballRadius = 3.0;
  static const double _initialBallSpeed = 120.0;
  static const double _ballSpeedIncrement = 8.0;
  static const double _maxBallSpeed = 300.0;
  static const double _aiBaseSpeed = 90.0;

  late _Paddle _playerPaddle;
  late _Paddle _aiPaddle;
  late _Ball _ball;
  late _LeftWall _leftWall;
  late _RightWall _rightWall;
  late SharedScreenFlash _screenFlash;

  double _ballSpeed = _initialBallSpeed;
  bool _serving = true;
  final Random _rng = Random();

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;

    // Walls (left and right boundaries).
    _leftWall = _LeftWall(
      position: Vector2(0, 0),
      size: Vector2(1, res.y),
    );
    _rightWall = _RightWall(
      position: Vector2(res.x - 1, 0),
      size: Vector2(1, res.y),
    );

    // Player paddle (bottom).
    _playerPaddle = _Paddle(
      position: Vector2(
        (res.x - _paddleWidth) / 2,
        res.y - _paddleMargin - _paddleHeight,
      ),
      size: Vector2(_paddleWidth, _paddleHeight),
      paint: Paint()..color = Pico8Palette.blue,
      highlightColor: Pico8Palette.lightGrey,
      isPlayer: true,
    );

    // AI paddle (top).
    _aiPaddle = _Paddle(
      position: Vector2(
        (res.x - _paddleWidth) / 2,
        _paddleMargin,
      ),
      size: Vector2(_paddleWidth, _paddleHeight),
      paint: Paint()..color = Pico8Palette.red,
      highlightColor: Pico8Palette.orange,
      isPlayer: false,
    );

    // Ball.
    _ball = _Ball(
      position: Vector2(res.x / 2, res.y / 2),
      radius: _ballRadius,
    );

    // Ball trail effect.
    final ballTrail = _BallTrail(ball: _ball);

    // Center dashed line.
    final centerLine = _DashedCenterLine(resolution: res);

    // Screen flash overlay (invisible by default).
    _screenFlash = SharedScreenFlash(size: res.clone());

    // Score / lives HUD.
    final hud = SharedHudComponent(game: this, scorePosition: Vector2(4, res.y / 2 + 8), livesPosition: Vector2(res.x - 52, res.y / 2 + 8));

    world.addAll([
      _leftWall,
      _rightWall,
      ballTrail,
      _playerPaddle,
      _aiPaddle,
      _ball,
      centerLine,
      _screenFlash,
      hud,
    ]);

    _serve();
  }

  /// Launch the ball from the center in a random-ish direction.
  void _serve() {
    _serving = true;
    _ballSpeed = _initialBallSpeed;

    final res = BaseArcadeGame.resolution;
    _ball.position.setValues(res.x / 2, res.y / 2);

    // Random angle biased downward (toward player) or upward.
    final goingDown = _rng.nextBool();
    final angle = (_rng.nextDouble() * 0.8 + 0.2) * (goingDown ? 1 : -1);
    final xDir = _rng.nextBool() ? 1.0 : -1.0;

    _ball.velocity
      ..setValues(xDir * cos(angle), sin(angle))
      ..normalize()
      ..scale(_ballSpeed);

    _serving = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_serving) return;

    final res = BaseArcadeGame.resolution;

    // --- AI paddle tracking ---
    final aiCenter = _aiPaddle.position.x + _paddleWidth / 2;
    final ballCenter = _ball.position.x;
    final diff = ballCenter - aiCenter;
    final aiSpeed = _aiBaseSpeed + (_ballSpeed * 0.35);
    final maxMove = aiSpeed * dt;

    if (diff.abs() > 2) {
      _aiPaddle.position.x += diff.sign * min(diff.abs(), maxMove);
    }
    _aiPaddle.position.x =
        _aiPaddle.position.x.clamp(1, res.x - 1 - _paddleWidth);

    // --- Ball scoring zones ---
    // Ball passed AI paddle (top) → player scores.
    if (_ball.position.y - _ballRadius < 0) {
      _spawnScorePopup(_ball.position.clone());
      score += 10;
      _serve();
      return;
    }

    // Ball passed player paddle (bottom) → lose a life.
    if (_ball.position.y + _ballRadius > res.y) {
      lives -= 1;
      _screenFlash.trigger();
      if (lives <= 0) {
        onGameOver();
      } else {
        _serve();
      }
      return;
    }
  }

  /// Called when the ball hits any paddle.
  void _onPaddleHit(_Paddle paddle) {
    // Reverse vertical direction.
    _ball.velocity.y = -_ball.velocity.y;

    // Adjust horizontal angle based on where the ball hit the paddle.
    final paddleCenter = paddle.position.x + _paddleWidth / 2;
    final hitOffset = (_ball.position.x - paddleCenter) / (_paddleWidth / 2);
    _ball.velocity.x = hitOffset * _ballSpeed * 0.8;

    // Nudge ball out of paddle to prevent double collision.
    if (paddle.isPlayer) {
      _ball.position.y = paddle.position.y - _ballRadius - 1;
    } else {
      _ball.position.y = paddle.position.y + _paddleHeight + _ballRadius + 1;
    }

    // Speed up.
    _ballSpeed = min(_ballSpeed + _ballSpeedIncrement, _maxBallSpeed);
    _ball.velocity.normalize();
    _ball.velocity.scale(_ballSpeed);

    // Visual effects: paddle flash + particle sparks.
    paddle.flash();
    _spawnPaddleParticles(paddle);
  }

  /// Called when the ball hits a side wall.
  void _onWallHit({required bool isLeft}) {
    _ball.velocity.x = -_ball.velocity.x;
    final res = BaseArcadeGame.resolution;
    if (isLeft) {
      _ball.position.x = 1 + _ballRadius + 1;
    } else {
      _ball.position.x = res.x - 1 - _ballRadius - 1;
    }
  }

  /// Spawn a floating "+10" popup at the given position.
  void _spawnScorePopup(Vector2 pos) {
    world.add(SharedScorePopup(position: pos, lifetime: 0.5, driftSpeed: 40.0));
  }

  /// Spawn 4-6 particle sparks at the paddle collision point.
  void _spawnPaddleParticles(_Paddle paddle) {
    final count = 4 + _rng.nextInt(3); // 4 to 6 particles
    final colors = [
      Pico8Palette.white,
      Pico8Palette.yellow,
      Pico8Palette.blue,
    ];

    // Collision point is near the ball's current position, at the paddle edge.
    final spawnY = paddle.isPlayer
        ? paddle.position.y
        : paddle.position.y + _paddleHeight;

    for (int i = 0; i < count; i++) {
      final vx = (_rng.nextDouble() - 0.5) * 120;
      final vy = (paddle.isPlayer ? -1.0 : 1.0) *
          (_rng.nextDouble() * 60 + 20);
      final color = colors[_rng.nextInt(colors.length)];
      world.add(_Particle(
        position: Vector2(_ball.position.x + (_rng.nextDouble() - 0.5) * 6,
            spawnY),
        velocity: Vector2(vx, vy),
        color: color,
      ));
    }
  }

  // --- Drag input for player paddle ---

  @override
  void onDragUpdate(DragUpdateEvent event) {
    final res = BaseArcadeGame.resolution;
    // Convert screen-space delta to game-space using camera.
    final worldDelta = event.localDelta;
    _playerPaddle.position.x += worldDelta.x;
    _playerPaddle.position.x =
        _playerPaddle.position.x.clamp(1, res.x - 1 - _paddleWidth);
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _ballSpeed = _initialBallSpeed;

    final res = BaseArcadeGame.resolution;
    _playerPaddle.position.setValues(
      (res.x - _paddleWidth) / 2,
      res.y - _paddleMargin - _paddleHeight,
    );
    _aiPaddle.position.setValues(
      (res.x - _paddleWidth) / 2,
      _paddleMargin,
    );

    _serve();
  }

  @override
  void onGameOver() {
    _ball.velocity.setZero();
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Paddle component with highlight stripe and flash effect
// ---------------------------------------------------------------------------

class _Paddle extends RectangleComponent with CollisionCallbacks {
  _Paddle({
    required super.position,
    required super.size,
    required Paint paint,
    required this.highlightColor,
    required this.isPlayer,
  })  : _originalColor = paint.color,
        super(paint: paint);

  final bool isPlayer;
  final Color highlightColor;
  final Color _originalColor;

  double _flashTimer = 0;
  static const double _flashDuration = 0.1;
  bool _flashing = false;

  final Paint _highlightPaint = Paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
    _highlightPaint.color = highlightColor;
  }

  /// Briefly flash the paddle white.
  void flash() {
    _flashing = true;
    _flashTimer = _flashDuration;
    paint.color = Pico8Palette.white;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_flashing) {
      _flashTimer -= dt;
      if (_flashTimer <= 0) {
        _flashing = false;
        paint.color = _originalColor;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Draw a 1px highlight stripe on top of the paddle.
    if (!_flashing) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, 1),
        _highlightPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Ball component
// ---------------------------------------------------------------------------

class _Ball extends CircleComponent with CollisionCallbacks {
  _Ball({
    required Vector2 position,
    required double radius,
  }) : super(
          position: position,
          radius: radius,
          anchor: Anchor.center,
          paint: Paint()..color = Pico8Palette.white,
        );

  final Vector2 velocity = Vector2.zero();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.add(velocity * dt);
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    final game = findParent<World>()?.parent;
    if (game is! PongGame) return;

    if (other is _Paddle) {
      game._onPaddleHit(other);
    } else if (other is _LeftWall) {
      game._onWallHit(isLeft: true);
    } else if (other is _RightWall) {
      game._onWallHit(isLeft: false);
    }
  }
}

// ---------------------------------------------------------------------------
// Ball trail effect: fading circles behind the ball
// ---------------------------------------------------------------------------

class _BallTrail extends PositionComponent {
  _BallTrail({required this.ball});

  final _Ball ball;

  static const int _maxPositions = 8;
  static const double _recordInterval = 0.016; // ~60fps sampling

  final List<Vector2> _positions = [];
  double _timeSinceRecord = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _timeSinceRecord += dt;
    if (_timeSinceRecord >= _recordInterval) {
      _timeSinceRecord = 0;
      _positions.add(ball.position.clone());
      if (_positions.length > _maxPositions) {
        _positions.removeAt(0);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final count = _positions.length;
    if (count < 2) return;

    for (int i = 0; i < count; i++) {
      final t = i / count; // 0.0 (oldest) to ~1.0 (newest)
      final opacity = (t * 0.5).clamp(0.0, 1.0);
      final radius = 1.0 + t * 2.0;

      final trailPaint = Paint()
        ..color = Pico8Palette.blue.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(_positions[i].x, _positions[i].y),
        radius,
        trailPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Wall components
// ---------------------------------------------------------------------------

class _LeftWall extends RectangleComponent with CollisionCallbacks {
  _LeftWall({required super.position, required super.size})
      : super(paint: Paint()..color = Pico8Palette.darkGrey);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }
}

class _RightWall extends RectangleComponent with CollisionCallbacks {
  _RightWall({required super.position, required super.size})
      : super(paint: Paint()..color = Pico8Palette.darkGrey);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }
}

// ---------------------------------------------------------------------------
// Improved dashed center line with lavender color and end dots
// ---------------------------------------------------------------------------

class _DashedCenterLine extends PositionComponent {
  _DashedCenterLine({required this.resolution});

  final Vector2 resolution;
  final Paint _linePaint = Paint()..color = Pico8Palette.lavender;
  final Paint _dotPaint = Paint()..color = Pico8Palette.lavender;

  static const double _dashWidth = 2.0;
  static const double _dashHeight = 4.0;
  static const double _dashGap = 6.0;
  static const double _dotSize = 3.0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final y = resolution.y / 2 - _dashHeight / 2;

    // Left end dot.
    canvas.drawRect(
      Rect.fromLTWH(1, resolution.y / 2 - _dotSize / 2, _dotSize, _dotSize),
      _dotPaint,
    );

    // Dashed line.
    double x = 4.0;
    while (x < resolution.x - 4) {
      canvas.drawRect(
        Rect.fromLTWH(x, y, _dashWidth, _dashHeight),
        _linePaint,
      );
      x += _dashWidth + _dashGap;
    }

    // Right end dot.
    canvas.drawRect(
      Rect.fromLTWH(resolution.x - 1 - _dotSize,
          resolution.y / 2 - _dotSize / 2, _dotSize, _dotSize),
      _dotPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Particle sparks on paddle hit
// ---------------------------------------------------------------------------

class _Particle extends RectangleComponent {
  _Particle({
    required super.position,
    required this.velocity,
    required Color color,
  }) : super(
          size: Vector2.all(2),
          paint: Paint()..color = color,
          anchor: Anchor.center,
        );

  final Vector2 velocity;

  static const double _lifetime = 0.3;
  double _elapsed = 0;
  late final Color _baseColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _baseColor = paint.color;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    position.add(velocity * dt);

    if (_elapsed >= _lifetime) {
      removeFromParent();
      return;
    }

    final opacity = (1.0 - (_elapsed / _lifetime)).clamp(0.0, 1.0);
    paint.color = _baseColor.withValues(alpha: opacity);
  }
}
