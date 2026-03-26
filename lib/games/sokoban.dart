import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import '../core/base_game.dart';
import '../core/palette.dart';

/// Sokoban (Push Box) — classic grid-based puzzle game.
///
/// Push all crates onto goal positions using swipe or keyboard controls.
/// Features 10 progressive levels, undo support, and move counting.
class SokobanGame extends BaseArcadeGame with DragCallbacks, KeyboardEvents {
  SokobanGame() : super(gameId: 'sokoban');

  static const int _cellSize = 16;
  static const int _gridW = 16; // 256 / 16
  static const int _gridH = 15; // 240 / 16
  static const int _hudRows = 1; // top row for HUD
  static const int _playH = _gridH - _hudRows; // 14 rows for gameplay

  // ---- State ----
  int _currentLevel = 0;
  int _moveCount = 0;
  int _pushCount = 0;
  bool _levelComplete = false;
  double _levelCompleteTimer = 0;

  // Parsed level data
  late List<List<_CellType>> _grid;
  final List<Point<int>> _boxes = [];
  final Set<Point<int>> _goals = {};
  Point<int> _player = const Point(0, 0);
  Point<int> _lastDir = const Point(0, 1); // facing down initially
  int _offsetX = 0;
  int _offsetY = 0;
  int _levelW = 0;
  int _levelH = 0;

  // Undo
  final List<_MoveRecord> _undoStack = [];

  // Goal pulse
  double _goalPulseTimer = 0;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    lives = 0; // Sokoban has no lives — hide hearts

    world.addAll([_SokobanRenderer(game: this), _HudBar(game: this)]);

    _loadLevel(0);
  }

  // ---- Level management ----

  void _loadLevel(int index) {
    _currentLevel = index;
    _moveCount = 0;
    _pushCount = 0;
    _levelComplete = false;
    _levelCompleteTimer = 0;
    _undoStack.clear();
    _boxes.clear();
    _goals.clear();

    final lines = _levels[index];
    _levelH = lines.length;
    _levelW = lines.fold(0, (mx, l) => l.length > mx ? l.length : mx);

    // Center level in playable area
    _offsetX = (_gridW - _levelW) ~/ 2;
    _offsetY = _hudRows + (_playH - _levelH) ~/ 2;

    // Parse grid
    _grid = List.generate(
      _levelH,
      (y) => List.generate(_levelW, (x) {
        if (x >= lines[y].length) return _CellType.void_;
        final ch = lines[y][x];
        switch (ch) {
          case '#':
            return _CellType.wall;
          case '.':
            _goals.add(Point(x, y));
            return _CellType.goal;
          case '+':
            _goals.add(Point(x, y));
            _player = Point(x, y);
            return _CellType.goal;
          case '*':
            _goals.add(Point(x, y));
            _boxes.add(Point(x, y));
            return _CellType.goal;
          case '\$':
            _boxes.add(Point(x, y));
            return _CellType.floor;
          case '@':
            _player = Point(x, y);
            return _CellType.floor;
          case ' ':
            return _CellType.floor;
          default:
            return _CellType.void_;
        }
      }),
    );

    // Update score display
    score = score; // triggers notifier
  }

  void _restartLevel() {
    _loadLevel(_currentLevel);
  }

  void _advanceLevel() {
    // Award points
    final bonus = max(10, 100 - _moveCount);
    score += 1000 + bonus;

    if (_currentLevel + 1 < _levels.length) {
      _levelComplete = true;
      _levelCompleteTimer = 1.5; // show "LEVEL CLEAR" for 1.5s
    } else {
      // All levels complete — victory!
      onGameOver();
    }
  }

  // ---- Core logic ----

  void _tryMove(Point<int> dir) {
    if (_levelComplete) return;

    _lastDir = dir;
    final target = Point(_player.x + dir.x, _player.y + dir.y);

    // Bounds check
    if (target.y < 0 ||
        target.y >= _levelH ||
        target.x < 0 ||
        target.x >= _levelW) {
      return;
    }

    // Wall check
    if (_grid[target.y][target.x] == _CellType.wall ||
        _grid[target.y][target.x] == _CellType.void_) {
      return;
    }

    // Box check
    final boxIdx = _boxes.indexWhere((b) => b == target);
    if (boxIdx >= 0) {
      final behind = Point(target.x + dir.x, target.y + dir.y);
      // Can't push out of bounds
      if (behind.y < 0 ||
          behind.y >= _levelH ||
          behind.x < 0 ||
          behind.x >= _levelW) {
        return;
      }
      // Can't push into wall
      if (_grid[behind.y][behind.x] == _CellType.wall ||
          _grid[behind.y][behind.x] == _CellType.void_) {
        return;
      }
      // Can't push into another box
      if (_boxes.any((b) => b == behind)) return;

      // Push valid
      _undoStack.add(
        _MoveRecord(playerFrom: _player, boxIndex: boxIdx, boxFrom: target),
      );
      _boxes[boxIdx] = behind;
      _pushCount++;
    } else {
      // Simple move
      _undoStack.add(
        _MoveRecord(playerFrom: _player, boxIndex: -1, boxFrom: null),
      );
    }

    _player = target;
    _moveCount++;

    // Check completion
    if (_goals.every((g) => _boxes.contains(g))) {
      _advanceLevel();
    }
  }

  void _undo() {
    if (_undoStack.isEmpty || _levelComplete) return;

    final record = _undoStack.removeLast();
    _player = record.playerFrom;
    _moveCount = max(0, _moveCount - 1);

    if (record.boxIndex >= 0 && record.boxFrom != null) {
      _boxes[record.boxIndex] = record.boxFrom!;
      _pushCount = max(0, _pushCount - 1);
    }
  }

  // ---- Update loop ----

  @override
  void update(double dt) {
    super.update(dt);
    _goalPulseTimer += dt;

    if (_levelComplete) {
      _levelCompleteTimer -= dt;
      if (_levelCompleteTimer <= 0) {
        _loadLevel(_currentLevel + 1);
      }
    }
  }

  // ---- Input: Swipe ----

  Vector2? _dragStart;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragStart = event.localPosition.clone();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_dragStart == null) return;

    final vx = event.velocity.x;
    final vy = event.velocity.y;

    if (vx.abs() < 50 && vy.abs() < 50) return;

    Point<int> dir;
    if (vx.abs() > vy.abs()) {
      dir = vx > 0 ? const Point(1, 0) : const Point(-1, 0);
    } else {
      dir = vy > 0 ? const Point(0, 1) : const Point(0, -1);
    }

    _tryMove(dir);
    _dragStart = null;
  }

  // ---- Input: Keyboard ----

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _tryMove(const Point(0, -1));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _tryMove(const Point(0, 1));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _tryMove(const Point(-1, 0));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _tryMove(const Point(1, 0));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyZ ||
        key == LogicalKeyboardKey.backspace) {
      _undo();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyR) {
      _restartLevel();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---- Lifecycle ----

  @override
  void resetGame() {
    score = 0;
    lives = 0;
    _loadLevel(0);
  }

  @override
  void onGameOver() {
    overlays.add('GameOver');
  }

  // ---- Level data ----
  // Standard Sokoban notation: # wall, ' ' floor, . goal,
  // $ box, @ player, * box-on-goal, + player-on-goal

  // Verified-solvable levels with step-by-step traced solutions.
  static const List<List<String>> _levels = [
    // Level 1: First Push (1 box, straight push — 1 move)
    ['######', '#    #', '# @\$.#', '#    #', '######'],
    // Level 2: First Turn (1 box, reposition to push down — 3 moves)
    ['######', '#    #', '# @\$ #', '#  . #', '######'],
    // Level 3: Two Boxes (2 boxes, 2 goals — 7 moves)
    [
      '#######',
      '#     #',
      '# .\$  #',
      '#  @  #',
      '# .\$  #',
      '#     #',
      '#######',
    ],
    // Level 4: Watch the Corners (dead corners, routing — 12 moves)
    ['########', '#.  #  #', '#   #  #', '#    \$ #', '#  @   #', '########'],
    // Level 5: The Detour (L-shaped path — 11 moves)
    [
      '########',
      '#      #',
      '#      #',
      '# .##  #',
      '#  ##  #',
      '#  ##\$ #',
      '#    @ #',
      '########',
    ],
    // Level 6: Right Order (box ordering matters — 9 moves)
    [
      '#######',
      '#  .  #',
      '#  \$  #',
      '#  \$ @#',
      '#  .  #',
      '#     #',
      '#######',
    ],
    // Level 7: Room Service (3 boxes, large room — 27 moves)
    [
      '##########',
      '#   @    #',
      '#  \$  \$  #',
      '#    #   #',
      '#  \$     #',
      '# ...    #',
      '##########',
    ],
    // Level 8: Tight Squeeze (narrow passages — 35 moves)
    [
      '#########',
      '#   #   #',
      '# \$   \$ #',
      '#  ###  #',
      '#  # #  #',
      '#  . .  #',
      '#   @   #',
      '#########',
    ],
    // Level 9: Crossroads (intersecting paths, 3 boxes — 29 moves)
    [
      '########',
      '# @    #',
      '#  \$   #',
      '## ## ##',
      '#  \$ . #',
      '#    . #',
      '#  \$ . #',
      '#      #',
      '########',
    ],
    // Level 10: The Vault (4 boxes, 2x2 goal chamber — 82 moves)
    [
      '##########',
      '#        #',
      '# \$\$  \$\$ #',
      '#   ##   #',
      '#  #..#  #',
      '#   ..   #',
      '#   @    #',
      '##########',
    ],
  ];
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

enum _CellType { void_, wall, floor, goal }

class _MoveRecord {
  const _MoveRecord({
    required this.playerFrom,
    required this.boxIndex,
    required this.boxFrom,
  });

  final Point<int> playerFrom;
  final int boxIndex; // -1 if no box pushed
  final Point<int>? boxFrom;
}

// ---------------------------------------------------------------------------
// Sokoban renderer: draws entire grid in one pass
// ---------------------------------------------------------------------------

class _SokobanRenderer extends PositionComponent {
  _SokobanRenderer({required this.game});

  final SokobanGame game;

  final Paint _wallPaint = Paint()..color = Pico8Palette.darkGrey;
  final Paint _wallHighlight = Paint()..color = Pico8Palette.lightGrey;
  final Paint _wallShadow = Paint()..color = Pico8Palette.black;
  final Paint _floorPaint = Paint()..color = Pico8Palette.darkBlue;
  final Paint _floorDot = Paint()
    ..color = Pico8Palette.darkGrey.withValues(alpha: 0.3);
  final Paint _boxPaint = Paint()..color = Pico8Palette.brown;
  final Paint _boxHighlight = Paint()
    ..color = Pico8Palette.orange
    ..strokeWidth = 1;
  final Paint _boxOnGoalPaint = Paint()..color = Pico8Palette.green;
  final Paint _boxOnGoalHighlight = Paint()
    ..color = Pico8Palette.yellow
    ..strokeWidth = 1;
  final Paint _playerPaint = Paint()..color = Pico8Palette.blue;
  final Paint _eyePaint = Paint()..color = Pico8Palette.white;
  final Paint _pupilPaint = Paint()..color = Pico8Palette.black;
  final Paint _outlinePaint = Paint()..color = Pico8Palette.black;

  // Level complete flash
  final Paint _flashPaint = Paint()..color = Pico8Palette.green;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final cs = SokobanGame._cellSize.toDouble();
    final ox = game._offsetX;
    final oy = game._offsetY;

    // Goal pulse
    final pulse = (sin(game._goalPulseTimer * 3.0) * 0.5 + 0.5);
    final goalColor = Color.lerp(
      Pico8Palette.red,
      Pico8Palette.darkPurple,
      pulse,
    )!;
    final goalPaint = Paint()..color = goalColor;

    // Draw grid cells
    for (int y = 0; y < game._levelH; y++) {
      for (int x = 0; x < game._levelW; x++) {
        final cell = game._grid[y][x];
        if (cell == _CellType.void_) continue;

        final px = (ox + x) * cs;
        final py = (oy + y) * cs;
        final rect = Rect.fromLTWH(px, py, cs, cs);

        // Floor base
        if (cell == _CellType.floor || cell == _CellType.goal) {
          canvas.drawRect(rect, _floorPaint);
          // Subtle floor dot
          canvas.drawRect(Rect.fromLTWH(px + 7, py + 7, 2, 2), _floorDot);
        }

        // Goal marker
        if (cell == _CellType.goal) {
          // Diamond shape (4px diamond centered)
          final cx = px + 8;
          final cy = py + 8;
          final path = Path()
            ..moveTo(cx, cy - 4)
            ..lineTo(cx + 4, cy)
            ..lineTo(cx, cy + 4)
            ..lineTo(cx - 4, cy)
            ..close();
          canvas.drawPath(path, goalPaint);
        }

        // Wall
        if (cell == _CellType.wall) {
          canvas.drawRect(rect, _wallPaint);
          // Top-left highlight
          canvas.drawRect(
            Rect.fromLTWH(px + 1, py + 1, cs - 2, 2),
            _wallHighlight,
          );
          canvas.drawRect(
            Rect.fromLTWH(px + 1, py + 3, 2, cs - 4),
            _wallHighlight,
          );
          // Bottom-right shadow
          canvas.drawRect(
            Rect.fromLTWH(px + 1, py + cs - 2, cs - 1, 1),
            _wallShadow,
          );
          canvas.drawRect(
            Rect.fromLTWH(px + cs - 2, py + 1, 1, cs - 2),
            _wallShadow,
          );
        }
      }
    }

    // Draw boxes
    for (int i = 0; i < game._boxes.length; i++) {
      final box = game._boxes[i];
      final px = (ox + box.x) * cs;
      final py = (oy + box.y) * cs;
      final onGoal = game._goals.contains(box);

      final fill = onGoal ? _boxOnGoalPaint : _boxPaint;
      final highlight = onGoal ? _boxOnGoalHighlight : _boxHighlight;

      // Box body (14x14, 1px inset)
      canvas.drawRect(Rect.fromLTWH(px + 1, py + 1, 14, 14), fill);
      // Outline
      canvas.drawRect(Rect.fromLTWH(px, py, cs, 1), _outlinePaint);
      canvas.drawRect(Rect.fromLTWH(px, py + cs - 1, cs, 1), _outlinePaint);
      canvas.drawRect(Rect.fromLTWH(px, py, 1, cs), _outlinePaint);
      canvas.drawRect(Rect.fromLTWH(px + cs - 1, py, 1, cs), _outlinePaint);
      // Cross pattern
      canvas.drawLine(
        Offset(px + 3, py + 3),
        Offset(px + 13, py + 13),
        highlight,
      );
      canvas.drawLine(
        Offset(px + 13, py + 3),
        Offset(px + 3, py + 13),
        highlight,
      );
    }

    // Draw player
    final pp = game._player;
    final ppx = (ox + pp.x) * cs;
    final ppy = (oy + pp.y) * cs;

    // Body (12x14, centered)
    canvas.drawRect(Rect.fromLTWH(ppx + 2, ppy + 1, 12, 14), _playerPaint);
    // Outline
    canvas.drawRect(Rect.fromLTWH(ppx + 2, ppy, 12, 1), _outlinePaint);
    canvas.drawRect(Rect.fromLTWH(ppx + 2, ppy + 15, 12, 1), _outlinePaint);
    canvas.drawRect(Rect.fromLTWH(ppx + 1, ppy + 1, 1, 14), _outlinePaint);
    canvas.drawRect(Rect.fromLTWH(ppx + 14, ppy + 1, 1, 14), _outlinePaint);

    // Eyes (2x2 white with 1x1 black pupil)
    canvas.drawRect(Rect.fromLTWH(ppx + 5, ppy + 4, 2, 2), _eyePaint);
    canvas.drawRect(Rect.fromLTWH(ppx + 9, ppy + 4, 2, 2), _eyePaint);

    // Pupils shift with direction
    final dir = game._lastDir;
    final pdx = dir.x.clamp(-1, 1).toDouble();
    final pdy = dir.y.clamp(-1, 1).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(ppx + 5 + pdx, ppy + 4 + pdy, 1, 1),
      _pupilPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(ppx + 10 + pdx, ppy + 4 + pdy, 1, 1),
      _pupilPaint,
    );

    // Level complete overlay
    if (game._levelComplete) {
      final alpha = (game._levelCompleteTimer / 1.5).clamp(0.0, 1.0) * 0.3;
      _flashPaint.color = Pico8Palette.green.withValues(alpha: alpha);
      canvas.drawRect(Rect.fromLTWH(0, 0, 256, 240), _flashPaint);

      final style = TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 8,
        fontFamily: 'PressStart2P',
      );
      TextPaint(style: style).render(canvas, 'LEVEL CLEAR!', Vector2(60, 112));
    }
  }
}

// ---------------------------------------------------------------------------
// HUD bar: level, moves, pushes, undo button
// ---------------------------------------------------------------------------

class _HudBar extends PositionComponent with TapCallbacks {
  _HudBar({required this.game});

  final SokobanGame game;

  late final TextPaint _yellowText;
  late final TextPaint _whiteText;
  late final TextPaint _greyText;
  final Paint _bgPaint = Paint()..color = Pico8Palette.darkGrey;

  // Undo button bounds
  final Rect _undoRect = const Rect.fromLTWH(224, 0, 32, 16);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _yellowText = TextPaint(
      style: TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 7,
        fontFamily: 'PressStart2P',
      ),
    );
    _whiteText = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 7,
        fontFamily: 'PressStart2P',
      ),
    );
    _greyText = TextPaint(
      style: TextStyle(
        color: Pico8Palette.lightGrey,
        fontSize: 7,
        fontFamily: 'PressStart2P',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Background bar
    canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 16), _bgPaint);

    // Level number
    _yellowText.render(canvas, 'LV${game._currentLevel + 1}', Vector2(4, 4));

    // Move count
    _whiteText.render(canvas, 'MV:${game._moveCount}', Vector2(72, 4));

    // Push count
    _greyText.render(canvas, 'PU:${game._pushCount}', Vector2(140, 4));

    // Undo button
    canvas.drawRect(
      const Rect.fromLTWH(226, 2, 26, 12),
      Paint()..color = Pico8Palette.darkBlue,
    );
    canvas.drawRect(
      const Rect.fromLTWH(226, 2, 26, 12),
      Paint()
        ..color = Pico8Palette.lavender
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _greyText.render(canvas, 'UND', Vector2(228, 4));
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    // Only respond to taps in the HUD area
    return point.y >= 0 && point.y <= 16 && point.x >= 0 && point.x <= 256;
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final pos = event.localPosition;
    if (_undoRect.contains(Offset(pos.x, pos.y))) {
      game._undo();
    }
  }
}
