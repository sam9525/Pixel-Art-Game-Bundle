import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

/// Classic Tetris arcade game with pixel-art aesthetics.
///
/// 10x20 playfield with SRS rotation, 7-bag randomizer, ghost piece,
/// lock delay, and line clear animations. Touch controls: swipe
/// left/right to move, swipe down for soft drop, swipe up for hard
/// drop, tap to rotate clockwise.
class TetrisGame extends BaseArcadeGame with DragCallbacks, TapCallbacks {
  TetrisGame() : super(gameId: 'tetris');

  // Board dimensions.
  static const int _cols = 10;
  static const int _rows = 20;
  static const int _cellSize = 10;

  // Board pixel offsets (centered horizontally: (256 - 100) / 2 = 78,
  // but spec says left edge at x=38 for aesthetic balance with side panels).
  static const double _boardX = 38;
  static const double _boardY = 20;

  // Piece colors indexed 0-6: I, O, T, S, Z, L, J.
  static List<Color> get _pieceColors => const [
        Pico8Palette.blue, // I
        Pico8Palette.yellow, // O
        Pico8Palette.darkPurple, // T
        Pico8Palette.green, // S
        Pico8Palette.red, // Z
        Pico8Palette.orange, // L
        Pico8Palette.lavender, // J
      ];

  /// All 7 tetrominoes, each with 4 rotation states.
  /// Each rotation state is a list of 4 (row, col) offsets.
  static const List<List<List<List<int>>>> _pieces = [
    // I
    [
      [[1, 0], [1, 1], [1, 2], [1, 3]],
      [[0, 2], [1, 2], [2, 2], [3, 2]],
      [[2, 0], [2, 1], [2, 2], [2, 3]],
      [[0, 1], [1, 1], [2, 1], [3, 1]],
    ],
    // O
    [
      [[0, 0], [0, 1], [1, 0], [1, 1]],
      [[0, 0], [0, 1], [1, 0], [1, 1]],
      [[0, 0], [0, 1], [1, 0], [1, 1]],
      [[0, 0], [0, 1], [1, 0], [1, 1]],
    ],
    // T
    [
      [[0, 0], [0, 1], [0, 2], [1, 1]],
      [[0, 0], [1, 0], [2, 0], [1, 1]],
      [[0, 1], [1, 0], [1, 1], [1, 2]],
      [[0, 1], [1, 0], [1, 1], [2, 1]],
    ],
    // S
    [
      [[0, 1], [0, 2], [1, 0], [1, 1]],
      [[0, 0], [1, 0], [1, 1], [2, 1]],
      [[0, 1], [0, 2], [1, 0], [1, 1]],
      [[0, 0], [1, 0], [1, 1], [2, 1]],
    ],
    // Z
    [
      [[0, 0], [0, 1], [1, 1], [1, 2]],
      [[0, 1], [1, 0], [1, 1], [2, 0]],
      [[0, 0], [0, 1], [1, 1], [1, 2]],
      [[0, 1], [1, 0], [1, 1], [2, 0]],
    ],
    // L
    [
      [[0, 0], [0, 1], [0, 2], [1, 0]],
      [[0, 0], [1, 0], [2, 0], [2, 1]],
      [[0, 2], [1, 0], [1, 1], [1, 2]],
      [[0, 0], [0, 1], [1, 1], [2, 1]],
    ],
    // J
    [
      [[0, 0], [0, 1], [0, 2], [1, 2]],
      [[0, 0], [1, 0], [2, 0], [0, 1]],
      [[0, 0], [1, 0], [1, 1], [1, 2]],
      [[0, 1], [1, 1], [2, 0], [2, 1]],
    ],
  ];

  /// SRS wall kick data for J, L, S, T, Z pieces.
  /// Key: (fromRotation, toRotation) encoded as fromRotation * 4 + toRotation.
  /// Each entry is a list of (row, col) offsets to try.
  static const Map<int, List<List<int>>> _wallKicks = {
    // 0 -> 1
    0 * 4 + 1: [[0, -1], [-1, -1], [2, 0], [2, -1]],
    // 1 -> 0
    1 * 4 + 0: [[0, 1], [1, 1], [-2, 0], [-2, 1]],
    // 1 -> 2
    1 * 4 + 2: [[0, 1], [1, 1], [-2, 0], [-2, 1]],
    // 2 -> 1
    2 * 4 + 1: [[0, -1], [-1, -1], [2, 0], [2, -1]],
    // 2 -> 3
    2 * 4 + 3: [[0, 1], [-1, 1], [2, 0], [2, 1]],
    // 3 -> 2
    3 * 4 + 2: [[0, -1], [1, -1], [-2, 0], [-2, -1]],
    // 3 -> 0
    3 * 4 + 0: [[0, -1], [1, -1], [-2, 0], [-2, -1]],
    // 0 -> 3
    0 * 4 + 3: [[0, 1], [-1, 1], [2, 0], [2, 1]],
  };

  /// SRS wall kick data for I piece.
  static const Map<int, List<List<int>>> _wallKicksI = {
    0 * 4 + 1: [[0, -2], [0, 1], [1, -2], [-2, 1]],
    1 * 4 + 0: [[0, 2], [0, -1], [-1, 2], [2, -1]],
    1 * 4 + 2: [[0, -1], [0, 2], [-2, -1], [1, 2]],
    2 * 4 + 1: [[0, 1], [0, -2], [2, 1], [-1, -2]],
    2 * 4 + 3: [[0, 2], [0, -1], [-1, 2], [2, -1]],
    3 * 4 + 2: [[0, -2], [0, 1], [1, -2], [-2, 1]],
    3 * 4 + 0: [[0, 1], [0, -2], [2, 1], [-1, -2]],
    0 * 4 + 3: [[0, -1], [0, 2], [-2, -1], [1, 2]],
  };

  final Random _rng = Random();

  // Board state: null means empty, Color means filled.
  late List<List<Color?>> _board;

  // Active piece state.
  int _currentPiece = 0;
  int _currentRotation = 0;
  int _currentRow = 0;
  int _currentCol = 0;

  // Next piece and bag.
  int _nextPiece = 0;
  List<int> _bag = [];

  // Timing.
  double _dropTimer = 0;
  double _dropInterval = 0.8;
  double _lockTimer = 0;
  bool _locking = false;
  static const double _lockDelay = 0.5;

  // Game progress.
  int _level = 1;
  int _linesCleared = 0;

  // Input state.
  bool _softDropping = false;

  // Game state.
  bool _alive = true;

  // Line clear animation.
  List<int> _clearingLines = [];
  double _clearTimer = 0;
  static const double _clearDuration = 0.2;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _board = List.generate(_rows, (_) => List.filled(_cols, null));

    world.addAll([
      _BoardRenderer(game: this),
      _PieceRenderer(game: this),
      _NextPieceRenderer(game: this),
      _HudComponent(game: this),
    ]);

    _fillBag();
    _nextPiece = _drawFromBag();
    _spawnPiece();
  }

  // --- 7-bag randomizer ---

  void _fillBag() {
    _bag = List.generate(7, (i) => i);
    _bag.shuffle(_rng);
  }

  int _drawFromBag() {
    if (_bag.isEmpty) _fillBag();
    return _bag.removeLast();
  }

  // --- Piece spawning ---

  void _spawnPiece() {
    _currentPiece = _nextPiece;
    _nextPiece = _drawFromBag();
    _currentRotation = 0;
    // Spawn at top center. Row -1 so piece appears to enter from top.
    _currentRow = _currentPiece == 0 ? -1 : 0; // I piece needs more room
    _currentCol = 3;
    _locking = false;
    _lockTimer = 0;
    _dropTimer = 0;
    _softDropping = false;

    // Check for game over: if piece immediately collides.
    if (!_isValidPosition(_currentPiece, _currentRotation, _currentRow, _currentCol)) {
      lives = 0;
      onGameOver();
    }
  }

  // --- Collision detection ---

  bool _isValidPosition(int piece, int rotation, int row, int col) {
    final cells = _pieces[piece][rotation];
    for (final cell in cells) {
      final r = row + cell[0];
      final c = col + cell[1];
      if (c < 0 || c >= _cols) return false;
      if (r >= _rows) return false;
      // Allow cells above the board (r < 0) for spawning.
      if (r >= 0 && _board[r][c] != null) return false;
    }
    return true;
  }

  // --- Movement ---

  bool _tryMove(int dRow, int dCol) {
    final newRow = _currentRow + dRow;
    final newCol = _currentCol + dCol;
    if (_isValidPosition(_currentPiece, _currentRotation, newRow, newCol)) {
      _currentRow = newRow;
      _currentCol = newCol;
      if (_locking) {
        _lockTimer = 0; // Reset lock delay on successful move.
      }
      return true;
    }
    return false;
  }

  bool _tryRotate() {
    final newRotation = (_currentRotation + 1) % 4;
    // Basic position check first.
    if (_isValidPosition(_currentPiece, newRotation, _currentRow, _currentCol)) {
      _currentRotation = newRotation;
      if (_locking) _lockTimer = 0;
      return true;
    }
    // Wall kick attempts.
    final kicks = _currentPiece == 0
        ? _wallKicksI[_currentRotation * 4 + newRotation]
        : _wallKicks[_currentRotation * 4 + newRotation];
    if (kicks != null) {
      for (final kick in kicks) {
        final kickRow = _currentRow + kick[0];
        final kickCol = _currentCol + kick[1];
        if (_isValidPosition(_currentPiece, newRotation, kickRow, kickCol)) {
          _currentRow = kickRow;
          _currentCol = kickCol;
          _currentRotation = newRotation;
          if (_locking) _lockTimer = 0;
          return true;
        }
      }
    }
    return false;
  }

  // --- Hard drop: find lowest valid row ---

  int _ghostRow() {
    int testRow = _currentRow;
    while (_isValidPosition(_currentPiece, _currentRotation, testRow + 1, _currentCol)) {
      testRow++;
    }
    return testRow;
  }

  void _hardDrop() {
    final ghost = _ghostRow();
    score += (ghost - _currentRow) * 2; // Hard drop scoring.
    _currentRow = ghost;
    _lockPiece();
  }

  // --- Piece locking ---

  void _lockPiece() {
    final color = _pieceColors[_currentPiece];
    final cells = _pieces[_currentPiece][_currentRotation];
    for (final cell in cells) {
      final r = _currentRow + cell[0];
      final c = _currentCol + cell[1];
      if (r >= 0 && r < _rows && c >= 0 && c < _cols) {
        _board[r][c] = color;
      }
    }
    _locking = false;
    _lockTimer = 0;
    _checkLines();
  }

  // --- Line clearing ---

  void _checkLines() {
    _clearingLines = [];
    for (int r = 0; r < _rows; r++) {
      bool full = true;
      for (int c = 0; c < _cols; c++) {
        if (_board[r][c] == null) {
          full = false;
          break;
        }
      }
      if (full) _clearingLines.add(r);
    }

    if (_clearingLines.isNotEmpty) {
      _clearTimer = _clearDuration;
      // Score based on number of lines.
      final count = _clearingLines.length;
      int points;
      switch (count) {
        case 1:
          points = 100 * _level;
          break;
        case 2:
          points = 300 * _level;
          break;
        case 3:
          points = 500 * _level;
          break;
        default:
          points = 800 * _level;
      }
      score += points;

      // Spawn score popup at the middle of cleared rows.
      final avgRow = _clearingLines.reduce((a, b) => a + b) / _clearingLines.length;
      world.add(SharedScorePopup(
        position: Vector2(
          _boardX + (_cols * _cellSize) / 2,
          _boardY + avgRow * _cellSize,
        ),
        points: points,
      ));

      // Spawn line clear effect.
      world.add(_LineClearEffect(
        game: this,
        rows: List.from(_clearingLines),
      ));
    } else {
      _spawnPiece();
    }
  }

  void _finishLineClear() {
    // Remove cleared rows from bottom to top, shift everything down.
    final sorted = List<int>.from(_clearingLines)..sort();
    for (final row in sorted.reversed) {
      _board.removeAt(row);
    }
    // Add empty rows at the top.
    for (int i = 0; i < sorted.length; i++) {
      _board.insert(0, List.filled(_cols, null));
    }

    _linesCleared += _clearingLines.length;
    // Level up every 10 lines.
    _level = (_linesCleared ~/ 10) + 1;
    _dropInterval = (0.8 - (_level - 1) * 0.06).clamp(0.1, 0.8);

    _clearingLines = [];
    _clearTimer = 0;
    _spawnPiece();
  }

  // --- Game loop ---

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive) return;

    // Line clear animation in progress.
    if (_clearingLines.isNotEmpty) {
      _clearTimer -= dt;
      if (_clearTimer <= 0) {
        _finishLineClear();
      }
      return; // Pause game during line clear animation.
    }

    // Gravity / drop timer.
    final interval = _softDropping ? 0.05 : _dropInterval;
    _dropTimer += dt;
    while (_dropTimer >= interval) {
      _dropTimer -= interval;
      if (!_tryMove(1, 0)) {
        // Can't move down — start or continue lock delay.
        if (!_locking) {
          _locking = true;
          _lockTimer = 0;
        }
        break;
      } else {
        // Piece moved down successfully.
        if (_softDropping) score += 1; // Soft drop scoring.
        // If we were locking but now can move down, cancel lock.
        if (_locking) {
          _locking = false;
          _lockTimer = 0;
        }
      }
    }

    // Lock delay countdown.
    if (_locking) {
      _lockTimer += dt;
      if (_lockTimer >= _lockDelay) {
        _lockPiece();
      }
    }
  }

  // --- Touch input ---

  Vector2? _dragStart;
  int _dragCellsMoved = 0;
  bool _dragIsVertical = false;
  bool _dragDirectionDecided = false;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragStart = event.localPosition.clone();
    _dragCellsMoved = 0;
    _dragIsVertical = false;
    _dragDirectionDecided = false;
    _softDropping = false;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_dragStart == null || !_alive || _clearingLines.isNotEmpty) return;

    final current = event.localStartPosition + event.localDelta;
    final dx = current.x - _dragStart!.x;
    final dy = current.y - _dragStart!.y;

    // Decide drag direction after sufficient movement.
    if (!_dragDirectionDecided) {
      if (dx.abs() > 10 || dy.abs() > 10) {
        _dragIsVertical = dy.abs() > dx.abs();
        _dragDirectionDecided = true;
      } else {
        return;
      }
    }

    if (_dragIsVertical) {
      if (dy > 20) {
        // Dragging down: soft drop mode.
        _softDropping = true;
      }
    } else {
      // Horizontal movement: every 20px = 1 cell.
      final cellDelta = (dx / 20).truncate();
      final cellsToMove = cellDelta - _dragCellsMoved;
      if (cellsToMove > 0) {
        for (int i = 0; i < cellsToMove; i++) {
          _tryMove(0, 1);
        }
        _dragCellsMoved = cellDelta;
      } else if (cellsToMove < 0) {
        for (int i = 0; i < -cellsToMove; i++) {
          _tryMove(0, -1);
        }
        _dragCellsMoved = cellDelta;
      }
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _softDropping = false;

    if (!_alive || _clearingLines.isNotEmpty) {
      _dragStart = null;
      return;
    }

    // Check for hard drop: strong upward velocity.
    final vy = event.velocity.y;
    if (vy < -300) {
      _hardDrop();
    }

    _dragStart = null;
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (!_alive || _clearingLines.isNotEmpty) return;
    _tryRotate();
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _level = 1;
    _linesCleared = 0;
    _dropInterval = 0.8;
    _dropTimer = 0;
    _lockTimer = 0;
    _locking = false;
    _softDropping = false;
    _alive = true;
    _clearingLines = [];
    _clearTimer = 0;
    _board = List.generate(_rows, (_) => List.filled(_cols, null));
    _fillBag();
    _nextPiece = _drawFromBag();
    _spawnPiece();
  }

  @override
  void onGameOver() {
    _alive = false;
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Board renderer: border, grid lines, and locked cells
// ---------------------------------------------------------------------------

class _BoardRenderer extends PositionComponent {
  _BoardRenderer({required this.game});

  final TetrisGame game;

  final Paint _borderPaint = Paint()
    ..color = Pico8Palette.darkGrey
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _gridPaint = Paint()
    ..color = Pico8Palette.darkBlue.withValues(alpha: 0.3);
  final Paint _cellPaint = Paint();
  final Paint _outlinePaint = Paint()..color = Pico8Palette.black;
  final Paint _highlightPaint = Paint();

  @override
  int get priority => 0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = TetrisGame._cellSize;
    const bx = TetrisGame._boardX;
    const by = TetrisGame._boardY;
    const cols = TetrisGame._cols;
    const rows = TetrisGame._rows;
    final boardW = (cols * cs).toDouble();
    final boardH = (rows * cs).toDouble();

    // Border around playfield.
    canvas.drawRect(
      Rect.fromLTWH(bx - 1, by - 1, boardW + 2, boardH + 2),
      _borderPaint,
    );

    // Grid lines.
    for (int c = 0; c <= cols; c++) {
      canvas.drawLine(
        Offset(bx + c * cs, by),
        Offset(bx + c * cs, by + boardH),
        _gridPaint,
      );
    }
    for (int r = 0; r <= rows; r++) {
      canvas.drawLine(
        Offset(bx, by + r * cs),
        Offset(bx + boardW, by + r * cs),
        _gridPaint,
      );
    }

    // Locked cells.
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final color = game._board[r][c];
        if (color != null) {
          _drawCell(canvas, bx + c * cs, by + r * cs, cs.toDouble(), color);
        }
      }
    }
  }

  void _drawCell(Canvas canvas, double x, double y, double size, Color color) {
    // Black outline.
    _outlinePaint.color = Pico8Palette.black;
    canvas.drawRect(Rect.fromLTWH(x, y, size, size), _outlinePaint);

    // Filled interior.
    _cellPaint.color = color;
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, size - 2), _cellPaint);

    // Highlight on top and left edges (1px lighter).
    _highlightPaint.color = Pico8Palette.white.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, 1), _highlightPaint);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 1, size - 3), _highlightPaint);
  }
}

// ---------------------------------------------------------------------------
// Active piece and ghost piece renderer
// ---------------------------------------------------------------------------

class _PieceRenderer extends PositionComponent {
  _PieceRenderer({required this.game});

  final TetrisGame game;

  final Paint _cellPaint = Paint();
  final Paint _outlinePaint = Paint()..color = Pico8Palette.black;
  final Paint _highlightPaint = Paint();
  final Paint _ghostPaint = Paint();

  @override
  int get priority => 1;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!game._alive || game._clearingLines.isNotEmpty) return;

    const cs = TetrisGame._cellSize;
    const bx = TetrisGame._boardX;
    const by = TetrisGame._boardY;

    final piece = game._currentPiece;
    final rotation = game._currentRotation;
    final row = game._currentRow;
    final col = game._currentCol;
    final cells = TetrisGame._pieces[piece][rotation];
    final color = TetrisGame._pieceColors[piece];

    // Draw ghost piece.
    final ghostRow = game._ghostRow();
    if (ghostRow != row) {
      _ghostPaint.color = color.withValues(alpha: 0.3);
      for (final cell in cells) {
        final r = ghostRow + cell[0];
        final c = col + cell[1];
        if (r >= 0 && r < TetrisGame._rows) {
          canvas.drawRect(
            Rect.fromLTWH(bx + c * cs + 1, by + r * cs + 1,
                cs.toDouble() - 2, cs.toDouble() - 2),
            _ghostPaint,
          );
        }
      }
    }

    // Draw active piece.
    for (final cell in cells) {
      final r = row + cell[0];
      final c = col + cell[1];
      if (r >= 0 && r < TetrisGame._rows) {
        _drawCell(canvas, bx + c * cs, by + r * cs, cs.toDouble(), color);
      }
    }
  }

  void _drawCell(Canvas canvas, double x, double y, double size, Color color) {
    _outlinePaint.color = Pico8Palette.black;
    canvas.drawRect(Rect.fromLTWH(x, y, size, size), _outlinePaint);

    _cellPaint.color = color;
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, size - 2), _cellPaint);

    _highlightPaint.color = Pico8Palette.white.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, 1), _highlightPaint);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 1, size - 3), _highlightPaint);
  }
}

// ---------------------------------------------------------------------------
// Next piece preview renderer
// ---------------------------------------------------------------------------

class _NextPieceRenderer extends PositionComponent {
  _NextPieceRenderer({required this.game});

  final TetrisGame game;

  final Paint _cellPaint = Paint();
  final Paint _outlinePaint = Paint()..color = Pico8Palette.black;
  final Paint _highlightPaint = Paint();
  final Paint _bgPaint = Paint()..color = Pico8Palette.darkBlue;

  @override
  int get priority => 2;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!game._alive) return;

    const previewX = 158.0;
    const previewY = 50.0;
    const cs = 8.0; // Slightly smaller cells for preview.

    // Background box for next piece.
    canvas.drawRect(
      Rect.fromLTWH(previewX - 4, previewY - 4, 44, 40),
      _bgPaint,
    );

    final piece = game._nextPiece;
    final cells = TetrisGame._pieces[piece][0]; // Always show rotation 0.
    final color = TetrisGame._pieceColors[piece];

    // Center the piece in the preview area.
    // Find bounding box of the piece cells.
    int minR = 99, maxR = -1, minC = 99, maxC = -1;
    for (final cell in cells) {
      if (cell[0] < minR) minR = cell[0];
      if (cell[0] > maxR) maxR = cell[0];
      if (cell[1] < minC) minC = cell[1];
      if (cell[1] > maxC) maxC = cell[1];
    }
    final pieceW = (maxC - minC + 1) * cs;
    final pieceH = (maxR - minR + 1) * cs;
    final offsetX = previewX + (36 - pieceW) / 2 - minC * cs;
    final offsetY = previewY + (32 - pieceH) / 2 - minR * cs;

    for (final cell in cells) {
      final x = offsetX + cell[1] * cs;
      final y = offsetY + cell[0] * cs;
      _drawCell(canvas, x, y, cs, color);
    }
  }

  void _drawCell(Canvas canvas, double x, double y, double size, Color color) {
    _outlinePaint.color = Pico8Palette.black;
    canvas.drawRect(Rect.fromLTWH(x, y, size, size), _outlinePaint);

    _cellPaint.color = color;
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, size - 2), _cellPaint);

    _highlightPaint.color = Pico8Palette.white.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, size - 2, 1), _highlightPaint);
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 1, size - 3), _highlightPaint);
  }
}

// ---------------------------------------------------------------------------
// Line clear flash effect
// ---------------------------------------------------------------------------

class _LineClearEffect extends PositionComponent {
  _LineClearEffect({required this.game, required this.rows});

  final TetrisGame game;
  final List<int> rows;

  static const double _duration = 0.2;
  double _elapsed = 0;

  final Paint _flashPaint = Paint()..color = Pico8Palette.white;

  @override
  int get priority => 10;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1.0 - (_elapsed / _duration)).clamp(0.0, 1.0);
    _flashPaint.color = Pico8Palette.white.withValues(alpha: opacity);

    const cs = TetrisGame._cellSize;
    const bx = TetrisGame._boardX;
    const by = TetrisGame._boardY;
    final boardW = (TetrisGame._cols * cs).toDouble();

    for (final row in rows) {
      canvas.drawRect(
        Rect.fromLTWH(bx, by + row * cs, boardW, cs.toDouble()),
        _flashPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// HUD: SCORE, LEVEL, LINES, NEXT label
// ---------------------------------------------------------------------------

class _HudComponent extends PositionComponent {
  _HudComponent({required this.game});

  final TetrisGame game;

  late final TextPaint _labelPaint;
  late final TextPaint _valuePaint;

  @override
  int get priority => 5;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _labelPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.lightGrey,
        fontSize: 7,
        fontFamily: 'monospace',
      ),
    );
    _valuePaint = TextPaint(
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

    // Right panel starting at x=148.
    const px = 148.0;

    // NEXT label.
    _labelPaint.render(canvas, 'NEXT', Vector2(px + 16, 36));

    // SCORE.
    _labelPaint.render(canvas, 'SCORE', Vector2(px, 100));
    _valuePaint.render(canvas, '${game.score}', Vector2(px, 112));

    // LEVEL.
    _labelPaint.render(canvas, 'LEVEL', Vector2(px, 136));
    _valuePaint.render(canvas, '${game._level}', Vector2(px, 148));

    // LINES.
    _labelPaint.render(canvas, 'LINES', Vector2(px, 172));
    _valuePaint.render(canvas, '${game._linesCleared}', Vector2(px, 184));

    // Title at top.
    _valuePaint.render(canvas, 'TETRIS', Vector2(4, 4));
  }
}

