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
// Layout constants (256x240 canvas)
// ---------------------------------------------------------------------------

/// Grid: 16 columns x 15 rows x 16px = 256x240.
class _Grid {
  _Grid._();

  static const int cols = 16;
  static const int rows = 15;
  static const double cell = 16.0;

  static const int startRow = 14;
  static const int goalRow = 0;
  static const int medianRow = 7;
  static const int roadTop = 8;
  static const int roadBottom = 12;
  static const int riverTop = 1;
  static const int riverBottom = 5;

  static double rowY(int row) => row * cell;
  static double colX(int col) => col * cell;

  static bool isRoad(int row) => row >= roadTop && row <= roadBottom;
  static bool isRiver(int row) => row >= riverTop && row <= riverBottom;
  static bool isMedian(int row) => row == medianRow;
  static bool isGoal(int row) => row == goalRow;
  static bool isStart(int row) => row == startRow;
}

// ---------------------------------------------------------------------------
// Moving object types
// ---------------------------------------------------------------------------

enum _ObjType { car, truck, log, turtle }

class _MovingObj {
  _MovingObj({
    required this.type,
    required this.lane,
    required this.x,
    required this.speed,
    required this.width,
  });

  final _ObjType type;
  final int lane;
  double x;
  final double speed;
  final int width;
}

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------

enum _FrogState { alive, dying, dead, levelComplete, gameOver }

// ---------------------------------------------------------------------------
// Frogger - classic arcade crossing game
// ---------------------------------------------------------------------------

/// Guide the frog across roads and river to reach the goal slots.
///
/// Touch: tap left/right/up/down halves to jump.
/// Keyboard: Arrow keys / WASD.
class FroggerGame extends BaseArcadeGame with TapCallbacks, KeyboardEvents {
  FroggerGame() : super(gameId: 'frogger');

  // --- Frog state ---
  double _frogX = 0;
  double _frogY = 0;
  double _frogPixelX = 0;
  double _frogPixelY = 0;
  _FrogState _state = _FrogState.alive;
  int _goalCount = 0;

  // --- Timing ---
  double _timer = 0;
  static const double _startTime = 40.0;
  double _timeBonus = 0;
  double _deathTimer = 0;
  double _levelCompleteTimer = 0;

  // --- Level ---
  int _level = 1;

  // --- Lanes ---
  final List<_MovingObj> _objs = [];
  final Random _rng = Random();

  // --- Goals ---
  final List<bool> _goalSlots = [false, false, false, false, false];

  // --- Visual ---
  double _flicker = 0;

  // --- Screen flash ---
  late _ScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = _ScreenFlash(size: res.clone());

    world.addAll([
      _BgRenderer(game: this),
      _LaneRenderer(game: this),
      _ObjRenderer(game: this),
      _GoalRenderer(game: this),
      _FrogRenderer(game: this),
      _HudRenderer(game: this),
      _screenFlash,
    ]);

    _initLevel();
    _resetFrog();
  }

  void _initLevel() {
    _objs.clear();
    _goalSlots.fillRange(0, _goalSlots.length, false);

    final speedMult = 1.0 + (_level - 1) * 0.15;

    // Road lanes (rows 8-12)
    _spawnRoadLane(row: 8, speed: 40.0 * speedMult, type: _ObjType.car, gap: 5, objWidth: 2);
    _spawnRoadLane(row: 9, speed: -30.0 * speedMult, type: _ObjType.truck, gap: 4, objWidth: 4);
    _spawnRoadLane(row: 10, speed: 50.0 * speedMult, type: _ObjType.car, gap: 6, objWidth: 2);
    _spawnRoadLane(row: 11, speed: -45.0 * speedMult, type: _ObjType.car, gap: 5, objWidth: 2);
    _spawnRoadLane(row: 12, speed: 35.0 * speedMult, type: _ObjType.truck, gap: 4, objWidth: 4);

    // River lanes (rows 1-5)
    _spawnRiverLane(row: 5, speed: 25.0 * speedMult, type: _ObjType.log, gap: 3, objWidth: 5);
    _spawnRiverLane(row: 4, speed: -35.0 * speedMult, type: _ObjType.turtle, gap: 4, objWidth: 3);
    _spawnRiverLane(row: 3, speed: 30.0 * speedMult, type: _ObjType.log, gap: 3, objWidth: 4);
    _spawnRiverLane(row: 2, speed: -40.0 * speedMult, type: _ObjType.turtle, gap: 5, objWidth: 3);
    _spawnRiverLane(row: 1, speed: 20.0 * speedMult, type: _ObjType.log, gap: 3, objWidth: 6);
  }

  void _spawnRoadLane({
    required int row,
    required double speed,
    required _ObjType type,
    required int gap,
    required int objWidth,
  }) {
    const totalCells = _Grid.cols;
    int pos = _rng.nextInt(gap);
    while (pos < totalCells) {
      _objs.add(_MovingObj(
        type: type,
        lane: row,
        x: pos * _Grid.cell,
        speed: speed,
        width: objWidth,
      ));
      pos += objWidth + gap;
    }
  }

  void _spawnRiverLane({
    required int row,
    required double speed,
    required _ObjType type,
    required int gap,
    required int objWidth,
  }) {
    if (type == _ObjType.turtle) {
      // Spawn groups of 3 turtles
      int pos = _rng.nextInt(gap * 2);
      while (pos < _Grid.cols) {
        for (int t = 0; t < 3; t++) {
          _objs.add(_MovingObj(
            type: _ObjType.turtle,
            lane: row,
            x: (pos + t) * _Grid.cell,
            speed: speed,
            width: 1,
          ));
        }
        pos += objWidth + gap;
      }
    } else {
      int pos = _rng.nextInt(gap);
      while (pos < _Grid.cols) {
        _objs.add(_MovingObj(
          type: type,
          lane: row,
          x: pos * _Grid.cell,
          speed: speed,
          width: objWidth,
        ));
        pos += objWidth + gap;
      }
    }
  }

  void _resetFrog() {
    _frogX = _Grid.cols / 2.0 - 0.5;
    _frogY = _Grid.startRow.toDouble();
    _updateFrogPixelPos();
    _state = _FrogState.alive;
    _timer = _startTime;
  }

  void _updateFrogPixelPos() {
    _frogPixelX = _frogX * _Grid.cell;
    _frogPixelY = _frogY * _Grid.cell;
  }

  // -------------------------------------------------------------------------
  // Update
  // -------------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    _flicker += dt * 10;

    switch (_state) {
      case _FrogState.alive:
        _updateAlive(dt);
        break;
      case _FrogState.dying:
        _deathTimer += dt;
        if (_deathTimer >= 1.0) {
          _deathTimer = 0;
          _onDeathDone();
        }
        break;
      case _FrogState.levelComplete:
        _levelCompleteTimer += dt;
        if (_levelCompleteTimer >= 1.5) {
          _levelCompleteTimer = 0;
          _onLevelCompleteDone();
        }
        break;
      case _FrogState.dead:
      case _FrogState.gameOver:
        break;
    }
  }

  void _updateAlive(double dt) {
    final res = BaseArcadeGame.resolution.x;
    for (final obj in _objs) {
      obj.x += obj.speed * dt;
      final objW = obj.width * _Grid.cell;
      if (obj.speed > 0 && obj.x > res) {
        obj.x = -objW;
      } else if (obj.speed < 0 && obj.x + objW < 0) {
        obj.x = res;
      }
    }

    // River riding
    final frogRow = _frogY.round();
    if (_Grid.isRiver(frogRow)) {
      final onObj = _objUnderFrog();
      if (onObj != null) {
        _frogX += onObj.speed * dt / _Grid.cell;
        _frogPixelX = _frogX * _Grid.cell;
      }
    }

    // Boundary
    _frogX = _frogX.clamp(0.0, _Grid.cols - 1.0);
    _frogPixelX = _frogX * _Grid.cell;

    // Drowning
    if (_Grid.isRiver(frogRow)) {
      if (_objUnderFrog() == null) {
        _drown();
      }
    }

    // Timer
    _timer -= dt;
    if (_timer <= 0) {
      _timer = 0;
      _die();
    }
  }

  _MovingObj? _objUnderFrog() {
    final fcx = _frogPixelX + _Grid.cell / 2.0;
    final fcy = _frogPixelY + _Grid.cell - 2.0;

    for (final obj in _objs) {
      final objY = _Grid.rowY(obj.lane);
      if (fcy >= objY && fcy < objY + _Grid.cell) {
        final objW = obj.width * _Grid.cell;
        if (fcx >= obj.x && fcx < obj.x + objW) {
          return obj;
        }
      }
    }
    return null;
  }

  void _onDeathDone() {
    if (lives <= 0) {
      _state = _FrogState.gameOver;
      onGameOver();
    } else {
      _resetFrog();
    }
  }

  void _onLevelCompleteDone() {
    _level++;
    _initLevel();
    _resetFrog();
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _moveFrog(int dx, int dy) {
    if (_state != _FrogState.alive) return;

    final newRow = (_frogY + dy).round();
    final newCol = _frogX.round() + dx;

    if (newRow < 0 || newRow >= _Grid.rows) return;
    if (newCol < 0 || newCol >= _Grid.cols) return;

    final forward = dy < 0 && newRow < _frogY.round();

    _frogX = newCol.toDouble();
    _frogY = newRow.toDouble();
    _updateFrogPixelPos();

    if (forward && !_Grid.isGoal(newRow)) {
      score += 10;
    }

    if (_Grid.isGoal(newRow)) {
      _checkGoal();
    }

    final row = _frogY.round();
    if (_Grid.isRoad(row)) {
      _checkCarCollision();
    }
  }

  void _checkGoal() {
    final slotCol = _frogX.round();
    final slotIndex = _slotIndexFromCol(slotCol);

    if (slotIndex >= 0 && !_goalSlots[slotIndex]) {
      _goalSlots[slotIndex] = true;
      _goalCount++;

      _timeBonus = (_timer * 2.0).roundToDouble();
      score += 50 + _timeBonus.round();

      _state = _FrogState.levelComplete;
      _levelCompleteTimer = 0;

      if (_goalCount >= 5) {
        score += 1000;
        _goalCount = 0;
      }
    } else {
      _die();
    }
  }

  int _slotIndexFromCol(int col) {
    const slots = [1, 4, 7, 10, 13];
    for (int i = 0; i < slots.length; i++) {
      if ((col - slots[i]).abs() <= 1) return i;
    }
    return -1;
  }

  void _checkCarCollision() {
    final fcx = _frogPixelX + _Grid.cell / 2.0;
    final fcy = _frogPixelY + _Grid.cell / 2.0;

    for (final obj in _objs) {
      if (!_Grid.isRoad(obj.lane)) continue;
      final objY = _Grid.rowY(obj.lane);
      final objW = obj.width * _Grid.cell;

      if (fcy >= objY + 2.0 && fcy < objY + _Grid.cell - 2.0 &&
          fcx >= obj.x + 1.0 && fcx < obj.x + objW - 1.0) {
        _die();
        return;
      }
    }
  }

  void _die() {
    if (_state != _FrogState.alive) return;
    _state = _FrogState.dying;
    _deathTimer = 0;
    lives -= 1;
    _screenFlash.trigger();
  }

  void _drown() {
    if (_state != _FrogState.alive) return;
    _die();
  }

  // -------------------------------------------------------------------------
  // Input: Touch
  // -------------------------------------------------------------------------

  @override
  void onTapDown(TapDownEvent event) {
    if (_state != _FrogState.alive) return;

    final res = BaseArcadeGame.resolution;
    final lx = event.localPosition.x;
    final ly = event.localPosition.y;
    final thirdX = res.x / 3.0;
    final thirdY = res.y / 3.0;

    if (ly < thirdY) {
      _moveFrog(0, -1);
    } else if (ly > thirdY * 2.0) {
      _moveFrog(0, 1);
    } else if (lx < thirdX) {
      _moveFrog(-1, 0);
    } else if (lx > thirdX * 2.0) {
      _moveFrog(1, 0);
    }
  }

  // -------------------------------------------------------------------------
  // Input: Keyboard
  // -------------------------------------------------------------------------

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_state != _FrogState.alive) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.keyW:
        _moveFrog(0, -1);
        break;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.keyS:
        _moveFrog(0, 1);
        break;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyA:
        _moveFrog(-1, 0);
        break;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyD:
        _moveFrog(1, 0);
        break;
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _level = 1;
    _goalCount = 0;
    _initLevel();
    _resetFrog();
  }

  @override
  void onGameOver() {
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Background renderer
// ---------------------------------------------------------------------------

class _BgRenderer extends PositionComponent {
  _BgRenderer({required this.game});
  final FroggerGame game;

  final Paint _bg = Paint()..color = Pico8Palette.black;

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    final res = BaseArcadeGame.resolution;
    canvas.drawRect(Rect.fromLTWH(0.0, 0.0, res.x, res.y), _bg);
  }
}

// ---------------------------------------------------------------------------
// Lane renderer (road, grass, water)
// ---------------------------------------------------------------------------

class _LaneRenderer extends PositionComponent {
  _LaneRenderer({required this.game});
  final FroggerGame game;

  final Paint _road = Paint()..color = const Color(0xFF3A3A3A);
  final Paint _roadLine = Paint()
    ..color = Pico8Palette.yellow
    ..strokeWidth = 1.0;
  final Paint _grass = Paint()..color = Pico8Palette.darkGreen;
  final Paint _grassLight = Paint()..color = Pico8Palette.green;
  final Paint _water = Paint()..color = Pico8Palette.blue;
  final Paint _waterLine = Paint()
    ..color = Pico8Palette.darkBlue
    ..strokeWidth = 1.0;
  final Paint _medianGrass = Paint()..color = Pico8Palette.green;
  final Paint _startSafe = Paint()..color = Pico8Palette.darkGreen;
  final Paint _hedge = Paint()..color = Pico8Palette.darkGreen;

  @override
  int get priority => 1;

  @override
  void render(Canvas canvas) {
    final res = BaseArcadeGame.resolution;

    for (int row = 0; row < _Grid.rows; row++) {
      final y = _Grid.rowY(row);

      if (_Grid.isGoal(row)) {
        canvas.drawRect(Rect.fromLTWH(0.0, y, res.x, _Grid.cell), _grass);

      } else if (_Grid.isRiver(row)) {
        canvas.drawRect(Rect.fromLTWH(0.0, y, res.x, _Grid.cell), _water);

        final ripple = (game._flicker * 0.5).floor() % 3;
        for (double x = ripple * 16.0; x < res.x; x += 48.0) {
          final paint = Paint()..color = _waterLine.color.withValues(alpha: 0.4);
          canvas.drawRect(Rect.fromLTWH(x, y + 7.0, 12.0, 1.0), paint);
        }

      } else if (_Grid.isMedian(row)) {
        canvas.drawRect(Rect.fromLTWH(0.0, y, res.x, _Grid.cell), _medianGrass);
        for (double x = 0.0; x < res.x; x += 16.0) {
          canvas.drawRect(Rect.fromLTWH(x + 4.0, y + 2.0, 2.0, 4.0), _grassLight);
        }

      } else if (_Grid.isRoad(row)) {
        canvas.drawRect(Rect.fromLTWH(0.0, y, res.x, _Grid.cell), _road);

        if (row % 2 == 0) {
          for (double x = 0.0; x < res.x; x += 24.0) {
            canvas.drawRect(Rect.fromLTWH(x, y + 7.0, 12.0, 2.0), _roadLine);
          }
        }

      } else if (_Grid.isStart(row)) {
        canvas.drawRect(Rect.fromLTWH(0.0, y, res.x, _Grid.cell), _startSafe);
        for (double x = 0.0; x < res.x; x += 16.0) {
          canvas.drawRect(Rect.fromLTWH(x + 2.0, y + 1.0, 12.0, 6.0), _hedge);
          canvas.drawRect(Rect.fromLTWH(x + 4.0, y + 7.0, 8.0, 4.0), _hedge);
        }
      }
    }

    // Side hedges
    for (int row = 0; row < _Grid.rows; row++) {
      if (_Grid.isRoad(row) || _Grid.isRiver(row)) {
        final y = _Grid.rowY(row);
        canvas.drawRect(Rect.fromLTWH(0.0, y, 2.0, _Grid.cell), _hedge);
        canvas.drawRect(Rect.fromLTWH(res.x - 2.0, y, 2.0, _Grid.cell), _hedge);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Moving object renderer (cars, trucks, logs, turtles)
// ---------------------------------------------------------------------------

class _ObjRenderer extends PositionComponent {
  _ObjRenderer({required this.game});
  final FroggerGame game;

  final Paint _carBody = Paint()..color = Pico8Palette.red;
  final Paint _carWindow = Paint()..color = Pico8Palette.blue;
  final Paint _carOutline = Paint()..color = Pico8Palette.black;
  final Paint _truckBody = Paint()..color = Pico8Palette.lavender;
  final Paint _truckCab = Paint()..color = Pico8Palette.pink;
  final Paint _truckOutline = Paint()..color = Pico8Palette.black;
  final Paint _logBody = Paint()..color = Pico8Palette.brown;
  final Paint _logRing = Paint()..color = Pico8Palette.lightPeach;
  final Paint _logOutline = Paint()..color = Pico8Palette.black;
  final Paint _turtleShell = Paint()..color = Pico8Palette.darkGreen;
  final Paint _turtleBody = Paint()..color = Pico8Palette.green;
  final Paint _turtleOutline = Paint()..color = Pico8Palette.black;

  @override
  int get priority => 5;

  @override
  void render(Canvas canvas) {
    final flicker = game._flicker.floor() % 2;

    for (final obj in game._objs) {
      final y = _Grid.rowY(obj.lane);
      final w = obj.width * _Grid.cell;

      switch (obj.type) {
        case _ObjType.car:
          _renderCar(canvas, obj.x, y, w);
          break;
        case _ObjType.truck:
          _renderTruck(canvas, obj.x, y, w);
          break;
        case _ObjType.log:
          _renderLog(canvas, obj.x, y, w);
          break;
        case _ObjType.turtle:
          final diving = flicker == 0;
          if (diving) {
            final divePaint = Paint()..color = Pico8Palette.darkGreen.withValues(alpha: 0.5);
            canvas.drawRect(Rect.fromLTWH(obj.x, y, w, _Grid.cell), divePaint);
          } else {
            _renderTurtle(canvas, obj.x, y);
          }
          break;
      }
    }
  }

  void _renderCar(Canvas canvas, double x, double y, double w) {
    canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, w + 2.0, _Grid.cell + 2.0), _carOutline);
    canvas.drawRect(Rect.fromLTWH(x, y + 2.0, w, _Grid.cell - 4.0), _carBody);
    canvas.drawRect(Rect.fromLTWH(x + w - 5.0, y + 4.0, 4.0, _Grid.cell - 8.0), _carWindow);
    canvas.drawRect(Rect.fromLTWH(x + 1.0, y + 1.0, 3.0, 3.0), _carOutline);
    canvas.drawRect(Rect.fromLTWH(x + w - 4.0, y + 1.0, 3.0, 3.0), _carOutline);
    canvas.drawRect(Rect.fromLTWH(x + 1.0, y + _Grid.cell - 4.0, 3.0, 3.0), _carOutline);
    canvas.drawRect(Rect.fromLTWH(x + w - 4.0, y + _Grid.cell - 4.0, 3.0, 3.0), _carOutline);
  }

  void _renderTruck(Canvas canvas, double x, double y, double w) {
    canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, w + 2.0, _Grid.cell + 2.0), _truckOutline);
    final cabW = w < 4 * _Grid.cell ? w : 4 * _Grid.cell;
    canvas.drawRect(Rect.fromLTWH(x, y + 1.0, cabW, _Grid.cell - 2.0), _truckCab);
    canvas.drawRect(Rect.fromLTWH(x + cabW, y + 1.0, w - cabW, _Grid.cell - 2.0), _truckBody);
    canvas.drawRect(Rect.fromLTWH(x + 2.0, y + 3.0, 3.0, _Grid.cell - 6.0), _carWindow);
  }

  void _renderLog(Canvas canvas, double x, double y, double w) {
    canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, w + 2.0, _Grid.cell + 2.0), _logOutline);
    canvas.drawRect(Rect.fromLTWH(x, y + 2.0, w, _Grid.cell - 4.0), _logBody);
    for (double rx = x + 4.0; rx < x + w - 4.0; rx += 8.0) {
      canvas.drawRect(Rect.fromLTWH(rx, y + 6.0, 3.0, _Grid.cell - 12.0), _logRing);
    }
  }

  void _renderTurtle(Canvas canvas, double x, double y) {
    canvas.drawRect(Rect.fromLTWH(x + 1.0, y + 2.0, _Grid.cell - 2.0, _Grid.cell - 4.0), _turtleShell);
    canvas.drawRect(Rect.fromLTWH(x + 4.0, y + 5.0, _Grid.cell - 8.0, _Grid.cell - 10.0), _turtleBody);
    canvas.drawRect(Rect.fromLTWH(x, y + 1.0, _Grid.cell, _Grid.cell - 2.0), _turtleOutline);
  }
}

// ---------------------------------------------------------------------------
// Goal renderer (lily pads at top)
// ---------------------------------------------------------------------------

class _GoalRenderer extends PositionComponent {
  _GoalRenderer({required this.game});
  final FroggerGame game;

  static const List<int> _slots = [1, 4, 7, 10, 13];

  @override
  int get priority => 8;

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < _slots.length; i++) {
      final x = _Grid.colX(_slots[i]);
      final y = 0.0;
      final filled = game._goalSlots[i];
      final flicker = game._flicker.floor() % 2 == 0;

      if (filled) {
        final outline = Paint()..color = Pico8Palette.black;
        final filledPaint = Paint()..color = Pico8Palette.yellow;
        final frogEye = Paint()..color = Pico8Palette.black;
        canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, _Grid.cell + 2.0, _Grid.cell + 2.0), outline);
        canvas.drawRect(Rect.fromLTWH(x, y, _Grid.cell, _Grid.cell), filledPaint);
        canvas.drawRect(Rect.fromLTWH(x + 3.0, y + 3.0, 2.0, 2.0), frogEye);
        canvas.drawRect(Rect.fromLTWH(x + 11.0, y + 3.0, 2.0, 2.0), frogEye);
      } else {
        final outline = Paint()..color = Pico8Palette.black;
        final padPaint = Paint()..color = Pico8Palette.darkGreen;
        final padLight = Paint()..color = Pico8Palette.green;
        canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, _Grid.cell + 2.0, _Grid.cell + 2.0), outline);
        canvas.drawRect(Rect.fromLTWH(x, y, _Grid.cell, _Grid.cell), padPaint);
        canvas.drawRect(Rect.fromLTWH(x + 2.0, y + 2.0, _Grid.cell - 4.0, _Grid.cell - 4.0), padLight);
        if (flicker) {
          canvas.drawRect(Rect.fromLTWH(x + 6.0, y + 2.0, 4.0, 4.0), outline);
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Frog renderer
// ---------------------------------------------------------------------------

class _FrogRenderer extends PositionComponent {
  _FrogRenderer({required this.game});
  final FroggerGame game;

  final Paint _frogBody = Paint()..color = Pico8Palette.green;
  final Paint _frogDark = Paint()..color = Pico8Palette.darkGreen;
  final Paint _frogEye = Paint()..color = Pico8Palette.white;
  final Paint _frogPupil = Paint()..color = Pico8Palette.black;
  final Paint _frogOutline = Paint()..color = Pico8Palette.black;
  final Paint _frogLeg = Paint()..color = Pico8Palette.green;
  final Paint _frogLegDark = Paint()..color = Pico8Palette.darkGreen;
  final Paint _deathPaint = Paint()..color = Pico8Palette.red;
  final Paint _levelPaint = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 15;

  @override
  void render(Canvas canvas) {
    if (game._state == _FrogState.gameOver) return;

    final x = game._frogPixelX;
    final y = game._frogPixelY;

    if (game._state == _FrogState.dying) {
      final flash = game._deathTimer.floor() % 2 == 0;
      final paint = flash ? _deathPaint : _frogBody;
      canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, _Grid.cell + 2.0, _Grid.cell + 2.0), _frogOutline);
      canvas.drawRect(Rect.fromLTWH(x, y, _Grid.cell, _Grid.cell), paint);
      return;
    }

    if (game._state == _FrogState.levelComplete) {
      final flash = game._levelCompleteTimer.floor() % 2 == 0;
      final paint = flash ? _levelPaint : _frogBody;
      canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, _Grid.cell + 2.0, _Grid.cell + 2.0), _frogOutline);
      canvas.drawRect(Rect.fromLTWH(x, y, _Grid.cell, _Grid.cell), paint);
      canvas.drawRect(Rect.fromLTWH(x + 3.0, y + 3.0, 3.0, 3.0), _frogEye);
      canvas.drawRect(Rect.fromLTWH(x + 10.0, y + 3.0, 3.0, 3.0), _frogEye);
      canvas.drawRect(Rect.fromLTWH(x + 4.0, y + 4.0, 1.0, 1.0), _frogPupil);
      canvas.drawRect(Rect.fromLTWH(x + 11.0, y + 4.0, 1.0, 1.0), _frogPupil);
      return;
    }

    // Normal frog
    canvas.drawRect(Rect.fromLTWH(x - 1.0, y - 1.0, _Grid.cell + 2.0, _Grid.cell + 2.0), _frogOutline);
    canvas.drawRect(Rect.fromLTWH(x + 2.0, y + 4.0, _Grid.cell - 4.0, _Grid.cell - 6.0), _frogBody);
    canvas.drawRect(Rect.fromLTWH(x + 3.0, y + 1.0, _Grid.cell - 6.0, 5.0), _frogBody);
    canvas.drawRect(Rect.fromLTWH(x + 3.0, y + 1.0, 4.0, 4.0), _frogEye);
    canvas.drawRect(Rect.fromLTWH(x + 9.0, y + 1.0, 4.0, 4.0), _frogEye);
    canvas.drawRect(Rect.fromLTWH(x + 4.0, y + 2.0, 2.0, 2.0), _frogPupil);
    canvas.drawRect(Rect.fromLTWH(x + 10.0, y + 2.0, 2.0, 2.0), _frogPupil);
    canvas.drawRect(Rect.fromLTWH(x, y + 10.0, 3.0, 4.0), _frogLeg);
    canvas.drawRect(Rect.fromLTWH(x + _Grid.cell - 3.0, y + 10.0, 3.0, 4.0), _frogLeg);
    canvas.drawRect(Rect.fromLTWH(x + 1.0, y + 6.0, 2.0, 3.0), _frogLegDark);
    canvas.drawRect(Rect.fromLTWH(x + _Grid.cell - 3.0, y + 6.0, 2.0, 3.0), _frogLegDark);
    canvas.drawRect(Rect.fromLTWH(x + 6.0, y + 8.0, 4.0, 3.0), _frogDark);
  }
}

// ---------------------------------------------------------------------------
// HUD renderer (timer, level, etc.)
// ---------------------------------------------------------------------------

class _HudRenderer extends PositionComponent {
  _HudRenderer({required this.game});
  final FroggerGame game;

  late final TextPaint _labelPaint;
  late final TextPaint _valuePaint;
  late final TextPaint _warnPaint;
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
        fontSize: 6.0,
        fontFamily: 'PressStart2P',
      ),
    );
    _valuePaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 6.0,
        fontFamily: 'PressStart2P',
      ),
    );
    _warnPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.red,
        fontSize: 6.0,
        fontFamily: 'PressStart2P',
      ),
    );
    _msgPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 8.0,
        fontFamily: 'PressStart2P',
      ),
    );
    _smallPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.lightGrey,
        fontSize: 5.0,
        fontFamily: 'PressStart2P',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final res = BaseArcadeGame.resolution;

    // Timer bar
    final timerFrac = (game._timer / 40.0).clamp(0.0, 1.0);
    final timerColor = timerFrac > 0.25 ? Pico8Palette.green : Pico8Palette.red;
    final bgPaint = Paint()..color = Pico8Palette.darkBlue;
    final fillPaint = Paint()..color = timerColor;
    canvas.drawRect(Rect.fromLTWH(4.0, 2.0, 80.0, 4.0), bgPaint);
    canvas.drawRect(Rect.fromLTWH(4.0, 2.0, 80.0 * timerFrac, 4.0), fillPaint);

    final timerText = game._timer.ceil().toString().padLeft(2, '0');
    final timerPaint = timerFrac <= 0.25 ? _warnPaint : _valuePaint;
    timerPaint.render(canvas, timerText, Vector2(86.0, 0.0));

    // Level
    _labelPaint.render(canvas, 'LVL ${game._level}', Vector2(res.x / 2.0 - 18.0, 0.0));

    // Goals
    _valuePaint.render(canvas, '${game._goalCount}/5', Vector2(res.x - 40.0, 0.0));

    // Touch zone hints
    if (game._state == _FrogState.alive) {
      final arrowPaint = Paint()
        ..color = Pico8Palette.lightGrey.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      final thirdY = res.y / 3.0;
      final thirdX = res.x / 3.0;

      // UP arrow — triangle pointing up
      _drawArrow(canvas, arrowPaint, res.x / 2.0, thirdY / 2.0, 0);
      // DOWN arrow — triangle pointing down
      _drawArrow(canvas, arrowPaint, res.x / 2.0, thirdY * 2.0 + thirdY / 2.0, 2);
      // LEFT arrow — triangle pointing left (center of middle band)
      _drawArrow(canvas, arrowPaint, thirdX / 2.0, thirdY + thirdY / 2.0, 3);
      // RIGHT arrow — triangle pointing right (center of middle band)
      _drawArrow(canvas, arrowPaint, thirdX * 2.0 + thirdX / 2.0, thirdY + thirdY / 2.0, 1);
    }

    // State messages
    if (game._state == _FrogState.levelComplete) {
      _msgPaint.render(canvas, 'SAFE!', Vector2(res.x / 2.0 - 24.0, res.y / 2.0 - 10.0));
      if (game._timeBonus > 0) {
        _smallPaint.render(
          canvas, 'TIME BONUS +${game._timeBonus.round()}',
          Vector2(res.x / 2.0 - 48.0, res.y / 2.0 + 4.0),
        );
      }
    }

    if (game._state == _FrogState.dying) {
      TextPaint(
        style: TextStyle(
          color: Pico8Palette.red,
          fontSize: 8.0,
          fontFamily: 'PressStart2P',
        ),
      ).render(canvas, 'OUCH!', Vector2(res.x / 2.0 - 26.0, res.y / 2.0 - 4.0));
    }
  }

  // direction: 0=up, 1=right, 2=down, 3=left
  void _drawArrow(Canvas canvas, Paint paint, double cx, double cy, int direction) {
    const size = 6.0;
    final path = Path();

    switch (direction) {
      case 0: // up
        path.moveTo(cx, cy - size);
        path.lineTo(cx - size, cy + size);
        path.lineTo(cx + size, cy + size);
      case 1: // right
        path.moveTo(cx + size, cy);
        path.lineTo(cx - size, cy - size);
        path.lineTo(cx - size, cy + size);
      case 2: // down
        path.moveTo(cx, cy + size);
        path.lineTo(cx - size, cy - size);
        path.lineTo(cx + size, cy - size);
      case 3: // left
        path.moveTo(cx - size, cy);
        path.lineTo(cx + size, cy - size);
        path.lineTo(cx + size, cy + size);
    }

    path.close();
    canvas.drawPath(path, paint);
  }
}

// ---------------------------------------------------------------------------
// Screen flash
// ---------------------------------------------------------------------------

class _ScreenFlash extends RectangleComponent {
  _ScreenFlash({required Vector2 size})
      : super(
          position: Vector2.zero(),
          size: size,
          paint: Paint()..color = Pico8Palette.red,
          priority: 100,
        );

  double _timer = 0;
  static const double _duration = 0.2;
  bool _active = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint.color = Pico8Palette.red.withValues(alpha: 0.0);
  }

  void trigger() {
    _active = true;
    _timer = _duration;
    paint.color = Pico8Palette.red;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_active) {
      _timer -= dt;
      if (_timer <= 0) {
        _active = false;
        paint.color = Pico8Palette.red.withValues(alpha: 0.0);
      } else {
        final opacity = (_timer / _duration).clamp(0.0, 1.0);
        paint.color = Pico8Palette.red.withValues(alpha: opacity * 0.4);
      }
    }
  }
}
