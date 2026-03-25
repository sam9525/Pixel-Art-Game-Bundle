import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';

/// Classic Snake arcade game with pixel-art aesthetics.
///
/// Grid-based movement on a 32x30 cell board (8x8 cells) with a 2-cell
/// border of walls. Swipe to change direction, eat food to grow and score.
class SnakeGame extends BaseArcadeGame with DragCallbacks {
  SnakeGame() : super(gameId: 'snake');

  static const int _cellSize = 8;
  static const int _gridW = 32; // 256 / 8
  static const int _gridH = 30; // 240 / 8
  static const int _borderCells = 2;

  // Playfield bounds (inclusive cell coordinates).
  static const int _minX = _borderCells;
  static const int _maxX = _gridW - _borderCells - 1; // 29
  static const int _minY = _borderCells;
  static const int _maxY = _gridH - _borderCells - 1; // 27

  static const double _initialTickInterval = 0.15;
  static const double _tickSpeedStep = 0.01;
  static const double _minTickInterval = 0.06;

  final Random _rng = Random();

  // Snake state.
  final List<Point<int>> _segments = [];
  Point<int> _direction = const Point<int>(1, 0); // moving right
  Point<int> _nextDirection = const Point<int>(1, 0);
  bool _directionChangedThisTick = false;

  // Food state.
  Point<int> _food = const Point<int>(0, 0);
  int _foodsEaten = 0;

  // Timing.
  double _tickInterval = _initialTickInterval;
  double _tickAccumulator = 0;
  bool _alive = true;

  // Visual effect components (added to world in onLoad).
  late _ScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;

    _screenFlash = _ScreenFlash(size: res.clone());

    world.addAll([
      _BorderWalls(),
      _GridLines(),
      _SnakeRenderer(game: this),
      _FoodRenderer(game: this),
      _screenFlash,
      _HudComponent(game: this),
    ]);

    _initSnake();
    _spawnFood();
  }

  void _initSnake() {
    _segments.clear();
    // Start in the center of the playfield, 3 segments, heading right.
    final startX = (_minX + _maxX) ~/ 2;
    final startY = (_minY + _maxY) ~/ 2;
    for (int i = 2; i >= 0; i--) {
      _segments.add(Point<int>(startX - i, startY));
    }
    _direction = const Point<int>(1, 0);
    _nextDirection = const Point<int>(1, 0);
    _directionChangedThisTick = false;
  }

  void _spawnFood() {
    // Collect all empty cells.
    final occupied = <Point<int>>{..._segments};
    final emptyCells = <Point<int>>[];
    for (int x = _minX; x <= _maxX; x++) {
      for (int y = _minY; y <= _maxY; y++) {
        final p = Point<int>(x, y);
        if (!occupied.contains(p)) {
          emptyCells.add(p);
        }
      }
    }
    if (emptyCells.isEmpty) {
      // Board full — player essentially won. Treat as game over.
      onGameOver();
      return;
    }
    _food = emptyCells[_rng.nextInt(emptyCells.length)];
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive) return;

    _tickAccumulator += dt;
    while (_tickAccumulator >= _tickInterval) {
      _tickAccumulator -= _tickInterval;
      _tick();
      if (!_alive) break;
    }
  }

  void _tick() {
    // Apply queued direction.
    _direction = _nextDirection;
    _directionChangedThisTick = false;

    // Compute new head position.
    final head = _segments.last;
    final newHead = Point<int>(head.x + _direction.x, head.y + _direction.y);

    // Wall collision check.
    if (newHead.x < _minX ||
        newHead.x > _maxX ||
        newHead.y < _minY ||
        newHead.y > _maxY) {
      _loseLife();
      return;
    }

    // Self collision check (exclude the tail which will move away,
    // unless we just ate food — but we check before growing).
    // We check against all current segments. The tail will be removed
    // after this check only if we did NOT eat food.
    if (_segments.contains(newHead)) {
      _loseLife();
      return;
    }

    // Move: add new head.
    _segments.add(newHead);

    // Check food.
    if (newHead == _food) {
      // Grow: don't remove tail.
      score += 10;
      _foodsEaten += 1;

      // Spawn score popup.
      final popupPos = Vector2(
        newHead.x * _cellSize + _cellSize / 2,
        newHead.y * _cellSize.toDouble(),
      );
      world.add(_ScorePopup(position: popupPos));

      // Speed up every 5 foods.
      if (_foodsEaten % 5 == 0) {
        _tickInterval =
            (_tickInterval - _tickSpeedStep).clamp(_minTickInterval, 1.0);
      }

      _spawnFood();
    } else {
      // Remove tail (normal move).
      _segments.removeAt(0);
    }
  }

  void _loseLife() {
    lives -= 1;
    _screenFlash.trigger();

    if (lives <= 0) {
      _alive = false;
      onGameOver();
    } else {
      // Reset snake position but keep score.
      _initSnake();
      _tickAccumulator = 0;
      _spawnFood();
    }
  }

  // --- Swipe input via DragCallbacks ---

  Vector2? _dragStart;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragStart = event.localPosition.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // We handle direction change in onDragEnd for cleaner swipes.
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_dragStart == null) return;

    final velocity = event.velocity;
    final dx = velocity.x;
    final dy = velocity.y;

    // Determine primary swipe axis by comparing absolute velocities.
    if (dx.abs() < 50 && dy.abs() < 50) return; // Too slow, ignore.

    Point<int> newDir;
    if (dx.abs() > dy.abs()) {
      // Horizontal swipe.
      newDir = dx > 0 ? const Point<int>(1, 0) : const Point<int>(-1, 0);
    } else {
      // Vertical swipe.
      newDir = dy > 0 ? const Point<int>(0, 1) : const Point<int>(0, -1);
    }

    // Prevent 180-degree reversal.
    if (newDir.x == -_direction.x && newDir.y == -_direction.y) return;

    // Only allow one direction change per tick to prevent rapid double-turns.
    if (!_directionChangedThisTick) {
      _nextDirection = newDir;
      _directionChangedThisTick = true;
    }

    _dragStart = null;
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _foodsEaten = 0;
    _tickInterval = _initialTickInterval;
    _tickAccumulator = 0;
    _alive = true;

    _initSnake();
    _spawnFood();
  }

  @override
  void onGameOver() {
    _alive = false;
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Border walls rendered as darkGrey rectangles
// ---------------------------------------------------------------------------

class _BorderWalls extends PositionComponent {
  final Paint _wallPaint = Paint()..color = Pico8Palette.darkGrey;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = SnakeGame._cellSize;
    const gw = SnakeGame._gridW;
    const gh = SnakeGame._gridH;
    const border = SnakeGame._borderCells;

    final totalW = (gw * cs).toDouble();
    final totalH = (gh * cs).toDouble();
    final borderPx = (border * cs).toDouble();

    // Top wall.
    canvas.drawRect(Rect.fromLTWH(0, 0, totalW, borderPx), _wallPaint);
    // Bottom wall.
    canvas.drawRect(
        Rect.fromLTWH(0, totalH - borderPx, totalW, borderPx), _wallPaint);
    // Left wall.
    canvas.drawRect(
        Rect.fromLTWH(0, borderPx, borderPx, totalH - borderPx * 2),
        _wallPaint);
    // Right wall.
    canvas.drawRect(
        Rect.fromLTWH(
            totalW - borderPx, borderPx, borderPx, totalH - borderPx * 2),
        _wallPaint);
  }
}

// ---------------------------------------------------------------------------
// Faint grid lines in the background
// ---------------------------------------------------------------------------

class _GridLines extends PositionComponent {
  final Paint _gridPaint = Paint()
    ..color = Pico8Palette.darkBlue.withValues(alpha: 0.3);

  @override
  int get priority => -1;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = SnakeGame._cellSize;
    const gw = SnakeGame._gridW;
    const gh = SnakeGame._gridH;
    const border = SnakeGame._borderCells;

    final startX = border * cs;
    final startY = border * cs;
    final endX = (gw - border) * cs;
    final endY = (gh - border) * cs;

    // Vertical lines.
    for (int x = startX; x <= endX; x += cs) {
      canvas.drawLine(
        Offset(x.toDouble(), startY.toDouble()),
        Offset(x.toDouble(), endY.toDouble()),
        _gridPaint,
      );
    }
    // Horizontal lines.
    for (int y = startY; y <= endY; y += cs) {
      canvas.drawLine(
        Offset(startX.toDouble(), y.toDouble()),
        Offset(endX.toDouble(), y.toDouble()),
        _gridPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Snake renderer: draws head with eyes and body segments
// ---------------------------------------------------------------------------

class _SnakeRenderer extends PositionComponent {
  _SnakeRenderer({required this.game});

  final SnakeGame game;

  final Paint _headPaint = Paint()..color = Pico8Palette.green;
  final Paint _bodyPaint = Paint()..color = Pico8Palette.darkGreen;
  final Paint _eyePaint = Paint()..color = Pico8Palette.white;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final segments = game._segments;
    if (segments.isEmpty) return;

    const cs = SnakeGame._cellSize;

    // Draw body segments (all except last which is the head).
    for (int i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      canvas.drawRect(
        Rect.fromLTWH(
          seg.x * cs + 1.0,
          seg.y * cs + 1.0,
          cs - 2.0,
          cs - 2.0,
        ),
        _bodyPaint,
      );
    }

    // Draw head.
    final head = segments.last;
    final headRect = Rect.fromLTWH(
      head.x * cs.toDouble(),
      head.y * cs.toDouble(),
      cs.toDouble(),
      cs.toDouble(),
    );
    canvas.drawRect(headRect, _headPaint);

    // Draw eyes based on direction.
    final dir = game._direction;
    final hx = head.x * cs.toDouble();
    final hy = head.y * cs.toDouble();

    // Eye positions: two 1x1 pixel dots placed toward the front of the head.
    double eye1x, eye1y, eye2x, eye2y;

    if (dir.x == 1 && dir.y == 0) {
      // Moving right.
      eye1x = hx + 6;
      eye1y = hy + 2;
      eye2x = hx + 6;
      eye2y = hy + 5;
    } else if (dir.x == -1 && dir.y == 0) {
      // Moving left.
      eye1x = hx + 1;
      eye1y = hy + 2;
      eye2x = hx + 1;
      eye2y = hy + 5;
    } else if (dir.x == 0 && dir.y == -1) {
      // Moving up.
      eye1x = hx + 2;
      eye1y = hy + 1;
      eye2x = hx + 5;
      eye2y = hy + 1;
    } else {
      // Moving down.
      eye1x = hx + 2;
      eye1y = hy + 6;
      eye2x = hx + 5;
      eye2y = hy + 6;
    }

    canvas.drawRect(Rect.fromLTWH(eye1x, eye1y, 1, 1), _eyePaint);
    canvas.drawRect(Rect.fromLTWH(eye2x, eye2y, 1, 1), _eyePaint);
  }
}

// ---------------------------------------------------------------------------
// Food renderer with pulse animation and yellow highlight pixel
// ---------------------------------------------------------------------------

class _FoodRenderer extends PositionComponent {
  _FoodRenderer({required this.game});

  final SnakeGame game;

  final Paint _foodPaint = Paint()..color = Pico8Palette.red;
  final Paint _highlightPaint = Paint()..color = Pico8Palette.yellow;

  double _pulseTimer = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _pulseTimer += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = SnakeGame._cellSize;

    final food = game._food;
    final fx = food.x * cs.toDouble();
    final fy = food.y * cs.toDouble();

    // Pulse: oscillate inset between 0 and 1 pixel.
    final pulse = (sin(_pulseTimer * 6.0) * 0.5 + 0.5); // 0..1
    final inset = pulse * 1.0;

    canvas.drawRect(
      Rect.fromLTWH(fx + inset, fy + inset, cs - inset * 2, cs - inset * 2),
      _foodPaint,
    );

    // Yellow highlight pixel in top-left area of food.
    canvas.drawRect(
      Rect.fromLTWH(fx + 2, fy + 2, 1, 1),
      _highlightPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Score popup: floating "+10" text that drifts up and fades
// ---------------------------------------------------------------------------

class _ScorePopup extends PositionComponent {
  _ScorePopup({required super.position});

  static const double _lifetime = 0.5;
  static const double _driftSpeed = 40.0;

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
    TextPaint(style: style).render(canvas, '+10', Vector2.zero());
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

  final SnakeGame game;

  late final TextPaint _textPaint;

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
    // Render score and lives in the top border area.
    _textPaint.render(canvas, 'SCORE:${game.score}', Vector2(18, 4));
    _textPaint.render(canvas, 'LIVES:${game.lives}', Vector2(190, 4));
  }
}
