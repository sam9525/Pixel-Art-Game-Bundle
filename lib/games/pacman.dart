import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

/// Classic Pac-Man arcade game with pixel-art aesthetics.
///
/// Grid-based movement on a 28x31 cell maze (8x8 cells).
/// Swipe to change direction. Eat pellets, avoid ghosts, collect power pellets
/// to eat ghosts. Four ghosts with distinct AI personalities.
class PacManGame extends BaseArcadeGame with DragCallbacks, TapCallbacks {
  PacManGame() : super(gameId: 'pacman');

  // Grid dimensions – classic Pac-Man is 28×31 but we scale to fit 256×240.
  // Using 8px cells: 32×30 grid, with a 2-cell border for the maze walls.
  static const int cellSize = 8;
  static const int gridW = 32; // 256 / 8
  static const int gridH = 30; // 240 / 8

  // Maze occupies the center 28x28 area.
  static const int mazeOffsetX = 2;
  static const int mazeOffsetY = 1;
  static const int mazeW = 28;
  static const int mazeH = 28;

  // Tile types in the maze.
  static const int tWall = 1;
  static const int tEmpty = 0;
  static const int tPellet = 2;
  static const int tPower = 3;
  static const int tGhostHome = 4;
  static const int tGhostDoor = 5;

  // Movement directions.
  static const Point<int> dirUp = Point<int>(0, -1);
  static const Point<int> dirDown = Point<int>(0, 1);
  static const Point<int> dirLeft = Point<int>(-1, 0);
  static const Point<int> dirRight = Point<int>(1, 0);
  static const Point<int> dirNone = Point<int>(0, 0);

  final Random _rng = Random();

  // Maze state – grid of tile types.
  late List<List<int>> _maze;

  // Start state – game waits for tap before running.
  bool _waitingToStart = true;

  // Player state.
  // Row 21 in the maze template is open at x=14: '1300110000000000000011003001'
  Point<int> _pacPos = const Point<int>(14, 21);
  Point<int> _pacDir = dirLeft;
  Point<int> _pacNextDir = dirLeft;
  double _pacMouthAngle = 0.0; // animation
  bool _pacMouthClosing = false;

  // Ghost state.
  late List<_Ghost> _ghosts;

  // Power pellet state.
  bool _frightened = false;
  double _frightenedTimer = 0;
  static const double frightenedDuration = 6.0;
  int _frightenedGhostsEaten = 0;

  // Game timing.
  double _moveInterval = 0.15;
  double _moveAccumulator = 0;
  bool _alive = true;

  // Level & pellets.
  int _level = 1;
  int _totalPellets = 0;
  int _pelletsEaten = 0;

  // Scatter/chase mode cycling.
  double _modeTimer = 0;
  bool _scatterMode = true;
  int _modeCycle = 0;
  // Scatter durations (seconds) per cycle, then permanent chase.
  static const List<double> scatterDurations = [7, 7, 5, 5];
  static const List<double> chaseDurations = [20, 20, 20, double.infinity];

  // Fruit bonus.
  bool _fruitActive = false;
  double _fruitTimer = 0;
  final Point<int> _fruitPos = const Point<int>(14, 17);
  static const double fruitDuration = 9.0;

  // Visual effects.
  late SharedScreenFlash _screenFlash;
  final List<SharedScorePopup> _popups = [];

  // The maze layout template (28×28).
  // 1=wall, 0=empty(pellet), 3=power pellet, 4=ghost home, 5=ghost door
  static const List<String> _mazeTemplate = [
    '1111111111111111111111111111',
    '1000000000001110000000000001',
    '1011011111001110011111011001',
    '1311011111001110011111013001',
    '1011011111001110011111011001',
    '1000000000000000000000000001',
    '1011011011111111011011011001',
    '1011011011111111011011011001',
    '1000011000001110000011000001',
    '1111011111001110011111011111',
    '0000011111001110011111000000',
    '1111011000000000000011011111',
    '1111011014444444101101111111',
    '0000000014444444100000000000',
    '1111011015444444101101111111',
    '1111011000000000000011011111',
    '0000011111001110011111000000',
    '1111011111001110011111011111',
    '1000000000001110000000000001',
    '1011011111001110011111011001',
    '1011011111001110011111011001',
    '1300110000000000000011003001',
    '1110110110111111011011011101',
    '1110110110111111011011011101',
    '1000000010001110010000000001',
    '1011111111001110011111111001',
    '1011111111001110011111111001',
    '1000000000000000000000000001',
  ];

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _screenFlash = SharedScreenFlash(size: BaseArcadeGame.resolution.clone());

    _buildMaze();
    _initGhosts();

    world.addAll([
      _MazeRenderer(game: this),
      _PelletRenderer(game: this),
      _PacManRenderer(game: this),
      _GhostRenderer(game: this),
      _FruitRenderer(game: this),
      _screenFlash,
      _HudComponent(game: this),
      _ReadyOverlay(game: this),
    ]);
  }

  void _buildMaze() {
    _maze = List.generate(mazeH, (y) {
      return List.generate(mazeW, (x) {
        final c = _mazeTemplate[y][x];
        switch (c) {
          case '1':
            return tWall;
          case '3':
            return tPower;
          case '4':
            return tGhostHome;
          case '5':
            return tGhostDoor;
          default:
            return tPellet;
        }
      });
    });

    // Count pellets.
    _totalPellets = 0;
    for (int y = 0; y < mazeH; y++) {
      for (int x = 0; x < mazeW; x++) {
        if (_maze[y][x] == tPellet || _maze[y][x] == tPower) {
          _totalPellets++;
        }
      }
    }
    _pelletsEaten = 0;
  }

  void _initGhosts() {
    _ghosts = [
      // Blinky (red) – chases Pac-Man directly.
      _Ghost(
        name: 'blinky',
        color: Pico8Palette.red,
        startPos: const Point<int>(14, 11),
        scatterTarget: const Point<int>(25, 0),
        homePos: const Point<int>(14, 14),
        releaseDelay: 0,
      ),
      // Pinky (pink) – targets 4 tiles ahead of Pac-Man.
      _Ghost(
        name: 'pinky',
        color: Pico8Palette.pink,
        startPos: const Point<int>(13, 14),
        scatterTarget: const Point<int>(2, 0),
        homePos: const Point<int>(13, 14),
        releaseDelay: 2,
      ),
      // Inky (blue) – complex targeting using Blinky + Pac-Man.
      _Ghost(
        name: 'inky',
        color: Pico8Palette.blue,
        startPos: const Point<int>(15, 14),
        scatterTarget: const Point<int>(27, 27),
        homePos: const Point<int>(15, 14),
        releaseDelay: 5,
      ),
      // Clyde (orange) – chases when far, scatters when close.
      _Ghost(
        name: 'clyde',
        color: Pico8Palette.orange,
        startPos: const Point<int>(12, 14),
        scatterTarget: const Point<int>(0, 27),
        homePos: const Point<int>(12, 14),
        releaseDelay: 8,
      ),
    ];

    for (final g in _ghosts) {
      g.pos = g.startPos;
      g.dir = dirUp;
      g.state = _GhostState.home;
      g.releaseTimer = g.releaseDelay.toDouble();
    }

    // Blinky starts outside immediately.
    _ghosts[0].state = _GhostState.active;
    _ghosts[0].pos = const Point<int>(14, 11);
  }

  // Check if a maze cell is passable for Pac-Man.
  bool _isPassable(int x, int y) {
    if (x < 0 || x >= mazeW || y < 0 || y >= mazeH) {
      // Tunnel wrap-around rows.
      if (y == 13 && (x < 0 || x >= mazeW)) return true;
      return false;
    }
    final t = _maze[y][x];
    return t != tWall && t != tGhostHome && t != tGhostDoor;
  }

  // Check if a maze cell is passable for ghosts (can enter ghost home).
  bool _isGhostPassable(int x, int y, _Ghost ghost) {
    if (x < 0 || x >= mazeW || y < 0 || y >= mazeH) {
      if (y == 13 && (x < 0 || x >= mazeW)) return true;
      return false;
    }
    final t = _maze[y][x];
    if (t == tWall) return false;
    // Ghost door is passable only when leaving/entering home.
    if (t == tGhostDoor) {
      return ghost.state == _GhostState.home ||
          ghost.state == _GhostState.eaten;
    }
    if (t == tGhostHome) {
      return ghost.state == _GhostState.home ||
          ghost.state == _GhostState.eaten;
    }
    return true;
  }

  Point<int> _wrapPosition(Point<int> pos) {
    int x = pos.x;
    int y = pos.y;
    // Tunnel on row 13.
    if (y == 13) {
      if (x < 0) x = mazeW - 1;
      if (x >= mazeW) x = 0;
    }
    return Point<int>(x, y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive || _waitingToStart) return;

    // Pac-Man mouth animation.
    const mouthSpeed = 8.0;
    if (_pacMouthClosing) {
      _pacMouthAngle -= mouthSpeed * dt;
      if (_pacMouthAngle <= 0) {
        _pacMouthAngle = 0;
        _pacMouthClosing = false;
      }
    } else {
      _pacMouthAngle += mouthSpeed * dt;
      if (_pacMouthAngle >= 1.0) {
        _pacMouthAngle = 1.0;
        _pacMouthClosing = true;
      }
    }

    // Frightened timer.
    if (_frightened) {
      _frightenedTimer -= dt;
      if (_frightenedTimer <= 0) {
        _frightened = false;
        _frightenedGhostsEaten = 0;
        for (final g in _ghosts) {
          if (g.state == _GhostState.frightened) {
            g.state = _GhostState.active;
          }
        }
      }
    }

    // Mode cycling (scatter/chase).
    if (!_frightened) {
      _modeTimer += dt;
      final currentDuration = _scatterMode
          ? (_modeCycle < scatterDurations.length
              ? scatterDurations[_modeCycle]
              : 5)
          : (_modeCycle < chaseDurations.length
              ? chaseDurations[_modeCycle]
              : double.infinity);
      if (_modeTimer >= currentDuration && currentDuration != double.infinity) {
        _modeTimer = 0;
        _scatterMode = !_scatterMode;
        if (_scatterMode) _modeCycle++;
        // Reverse ghost directions on mode switch.
        for (final g in _ghosts) {
          if (g.state == _GhostState.active) {
            g.dir = Point<int>(-g.dir.x, -g.dir.y);
          }
        }
      }
    }

    // Fruit spawn.
    if (!_fruitActive &&
        (_pelletsEaten == 70 || _pelletsEaten == 170) &&
        _pelletsEaten > 0) {
      _fruitActive = true;
      _fruitTimer = fruitDuration;
    }
    if (_fruitActive) {
      _fruitTimer -= dt;
      if (_fruitTimer <= 0) _fruitActive = false;
    }

    // Ghost release timer.
    for (final g in _ghosts) {
      if (g.state == _GhostState.home) {
        g.releaseTimer -= dt;
        if (g.releaseTimer <= 0) {
          g.state = _GhostState.active;
          g.pos = const Point<int>(14, 11); // exit position
          g.dir = dirLeft;
        }
      }
    }

    // Movement tick.
    _moveAccumulator += dt;
    while (_moveAccumulator >= _moveInterval) {
      _moveAccumulator -= _moveInterval;
      _movePacMan();
      _moveGhosts();
      _checkCollisions();
      if (!_alive) break;
    }

    // Update popups.
    _popups.removeWhere((p) => p.parent == null);
  }

  void _movePacMan() {
    // Try the queued direction first.
    final nextPos = _wrapPosition(
      Point<int>(_pacPos.x + _pacNextDir.x, _pacPos.y + _pacNextDir.y),
    );
    if (_isPassable(nextPos.x, nextPos.y)) {
      _pacDir = _pacNextDir;
      _pacPos = nextPos;
    } else {
      // Continue in current direction.
      final contPos = _wrapPosition(
        Point<int>(_pacPos.x + _pacDir.x, _pacPos.y + _pacDir.y),
      );
      if (_isPassable(contPos.x, contPos.y)) {
        _pacPos = contPos;
      }
      // else: Pac-Man stops (wall ahead).
    }

    // Eat pellet.
    if (_pacPos.x >= 0 &&
        _pacPos.x < mazeW &&
        _pacPos.y >= 0 &&
        _pacPos.y < mazeH) {
      final tile = _maze[_pacPos.y][_pacPos.x];
      if (tile == tPellet) {
        _maze[_pacPos.y][_pacPos.x] = tEmpty;
        score += 10;
        _pelletsEaten++;
        _checkLevelComplete();
      } else if (tile == tPower) {
        _maze[_pacPos.y][_pacPos.x] = tEmpty;
        score += 50;
        _pelletsEaten++;
        _activateFrightened();
        _checkLevelComplete();
      }

      // Eat fruit.
      if (_fruitActive && _pacPos == _fruitPos) {
        _fruitActive = false;
        final fruitScore = _level * 100;
        score += fruitScore;
        _addPopup(_pacPos, fruitScore);
      }
    }
  }

  void _activateFrightened() {
    _frightened = true;
    _frightenedTimer = frightenedDuration;
    _frightenedGhostsEaten = 0;
    for (final g in _ghosts) {
      if (g.state == _GhostState.active) {
        g.state = _GhostState.frightened;
        // Reverse direction.
        g.dir = Point<int>(-g.dir.x, -g.dir.y);
      }
    }
  }

  void _checkLevelComplete() {
    if (_pelletsEaten >= _totalPellets) {
      _level++;
      _moveInterval = (_moveInterval - 0.005).clamp(0.06, 0.15);
      _buildMaze();
      _pacPos = const Point<int>(14, 21);
      _pacDir = dirLeft;
      _pacNextDir = dirLeft;
      _frightened = false;
      _fruitActive = false;
      _modeTimer = 0;
      _scatterMode = true;
      _modeCycle = 0;
      _initGhosts();
    }
  }

  void _moveGhosts() {
    for (int i = 0; i < _ghosts.length; i++) {
      final g = _ghosts[i];
      if (g.state == _GhostState.home) continue;

      // Eaten ghosts move fast toward home.
      final target = _getGhostTarget(i, g);

      // Get possible directions (exclude reverse unless only option).
      final reverse = Point<int>(-g.dir.x, -g.dir.y);
      final possible = <Point<int>>[];
      for (final d in [dirUp, dirLeft, dirDown, dirRight]) {
        if (d == reverse) continue;
        final np = _wrapPosition(Point<int>(g.pos.x + d.x, g.pos.y + d.y));
        if (_isGhostPassable(np.x, np.y, g)) {
          possible.add(d);
        }
      }

      if (possible.isEmpty) {
        // Dead end, reverse.
        final np =
            _wrapPosition(Point<int>(g.pos.x + reverse.x, g.pos.y + reverse.y));
        if (_isGhostPassable(np.x, np.y, g)) {
          possible.add(reverse);
        }
      }

      if (possible.isEmpty) continue;

      Point<int> bestDir;
      if (g.state == _GhostState.frightened) {
        // Random movement when frightened.
        bestDir = possible[_rng.nextInt(possible.length)];
      } else {
        // Choose direction that minimizes distance to target.
        double bestDist = double.infinity;
        bestDir = possible[0];
        for (final d in possible) {
          final np = _wrapPosition(Point<int>(g.pos.x + d.x, g.pos.y + d.y));
          final dist = _distance(np, target);
          if (dist < bestDist) {
            bestDist = dist;
            bestDir = d;
          }
        }
      }

      g.dir = bestDir;
      g.pos = _wrapPosition(Point<int>(g.pos.x + bestDir.x, g.pos.y + bestDir.y));

      // Check if eaten ghost reached home.
      if (g.state == _GhostState.eaten) {
        if (g.pos == g.homePos || g.pos == const Point<int>(14, 14)) {
          g.state = _GhostState.active;
          g.pos = const Point<int>(14, 11);
          g.dir = dirLeft;
        }
      }
    }
  }

  Point<int> _getGhostTarget(int index, _Ghost ghost) {
    if (ghost.state == _GhostState.eaten) {
      return ghost.homePos;
    }

    if (_scatterMode && ghost.state == _GhostState.active) {
      return ghost.scatterTarget;
    }

    // Chase mode targets.
    switch (index) {
      case 0: // Blinky – targets Pac-Man directly.
        return _pacPos;
      case 1: // Pinky – targets 4 tiles ahead.
        return Point<int>(
          _pacPos.x + _pacDir.x * 4,
          _pacPos.y + _pacDir.y * 4,
        );
      case 2: // Inky – vector from Blinky through point 2 ahead of Pac-Man.
        final ahead = Point<int>(
          _pacPos.x + _pacDir.x * 2,
          _pacPos.y + _pacDir.y * 2,
        );
        final blinky = _ghosts[0].pos;
        return Point<int>(
          ahead.x + (ahead.x - blinky.x),
          ahead.y + (ahead.y - blinky.y),
        );
      case 3: // Clyde – chases when far, scatters when close.
        final dist = _distance(ghost.pos, _pacPos);
        if (dist > 8) return _pacPos;
        return ghost.scatterTarget;
      default:
        return _pacPos;
    }
  }

  double _distance(Point<int> a, Point<int> b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  void _checkCollisions() {
    for (final g in _ghosts) {
      if (g.pos == _pacPos) {
        if (g.state == _GhostState.frightened) {
          // Eat ghost.
          g.state = _GhostState.eaten;
          _frightenedGhostsEaten++;
          final ghostScore = 200 * (1 << (_frightenedGhostsEaten - 1));
          score += ghostScore;
          _addPopup(_pacPos, ghostScore);
        } else if (g.state == _GhostState.active) {
          _loseLife();
          return;
        }
      }
    }
  }

  void _loseLife() {
    lives -= 1;
    _screenFlash.trigger();

    if (lives <= 0) {
      _alive = false;
      onGameOver();
    } else {
      // Reset positions, keep score and maze state.
      _pacPos = const Point<int>(14, 21);
      _pacDir = dirLeft;
      _pacNextDir = dirLeft;
      _moveAccumulator = 0;
      _frightened = false;
      _fruitActive = false;
      _modeTimer = 0;
      _scatterMode = true;
      _modeCycle = 0;
      _initGhosts();
    }
  }

  void _addPopup(Point<int> pos, int points) {
    final popup = SharedScorePopup(
      position: Vector2(
        (pos.x + mazeOffsetX) * cellSize + cellSize / 2,
        (pos.y + mazeOffsetY) * cellSize.toDouble(),
      ),
      points: points,
    );
    _popups.add(popup);
    world.add(popup);
  }

  // --- Tap to start ---

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_waitingToStart) {
      _waitingToStart = false;
    }
  }

  // --- Swipe input via DragCallbacks ---

  Vector2? _dragStart;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_waitingToStart) {
      _waitingToStart = false;
    }
    _dragStart = event.localPosition.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {}

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_dragStart == null) return;

    final velocity = event.velocity;
    final dx = velocity.x;
    final dy = velocity.y;

    if (dx.abs() < 50 && dy.abs() < 50) return;

    if (dx.abs() > dy.abs()) {
      _pacNextDir = dx > 0 ? dirRight : dirLeft;
    } else {
      _pacNextDir = dy > 0 ? dirDown : dirUp;
    }

    _dragStart = null;
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _level = 1;
    _moveInterval = 0.15;
    _moveAccumulator = 0;
    _alive = true;
    _frightened = false;
    _fruitActive = false;
    _modeTimer = 0;
    _scatterMode = true;
    _modeCycle = 0;
    _pacPos = const Point<int>(14, 21);
    _pacDir = dirLeft;
    _pacNextDir = dirLeft;
    _waitingToStart = true;

    _buildMaze();
    _initGhosts();
  }

  @override
  void onGameOver() {
    _alive = false;
    overlays.add('GameOver');
  }
}

// Ghost state enum.
enum _GhostState { home, active, frightened, eaten }

// Ghost data class.
class _Ghost {
  _Ghost({
    required this.name,
    required this.color,
    required this.startPos,
    required this.scatterTarget,
    required this.homePos,
    required this.releaseDelay,
  });

  final String name;
  final Color color;
  final Point<int> startPos;
  final Point<int> scatterTarget;
  final Point<int> homePos;
  final int releaseDelay;

  Point<int> pos = const Point<int>(0, 0);
  Point<int> dir = const Point<int>(0, -1);
  _GhostState state = _GhostState.home;
  double releaseTimer = 0;
}

// ---------------------------------------------------------------------------
// Maze renderer: draws walls as blue rectangles
// ---------------------------------------------------------------------------

class _MazeRenderer extends PositionComponent {
  _MazeRenderer({required this.game});

  final PacManGame game;

  final Paint _wallPaint = Paint()..color = Pico8Palette.darkBlue;
  final Paint _wallHighlight = Paint()..color = Pico8Palette.blue;
  final Paint _doorPaint = Paint()..color = Pico8Palette.pink;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = PacManGame.cellSize;
    const ox = PacManGame.mazeOffsetX;
    const oy = PacManGame.mazeOffsetY;

    for (int y = 0; y < PacManGame.mazeH; y++) {
      for (int x = 0; x < PacManGame.mazeW; x++) {
        final tile = game._maze[y][x];
        final px = (x + ox) * cs;
        final py = (y + oy) * cs;

        if (tile == PacManGame.tWall) {
          // Draw wall block.
          canvas.drawRect(
            Rect.fromLTWH(px.toDouble(), py.toDouble(), cs.toDouble(), cs.toDouble()),
            _wallPaint,
          );

          // Add blue highlight on edges adjacent to non-wall cells.
          _drawWallEdges(canvas, x, y, px.toDouble(), py.toDouble());
        } else if (tile == PacManGame.tGhostDoor) {
          // Ghost door – thin horizontal bar.
          canvas.drawRect(
            Rect.fromLTWH(px.toDouble(), py + 3.0, cs.toDouble(), 2),
            _doorPaint,
          );
        }
      }
    }
  }

  void _drawWallEdges(Canvas canvas, int x, int y, double px, double py) {
    final cs = PacManGame.cellSize.toDouble();

    // Check each neighbor; draw highlight edge if neighbor is not a wall.
    // Top edge.
    if (y > 0 && game._maze[y - 1][x] != PacManGame.tWall) {
      canvas.drawRect(Rect.fromLTWH(px, py, cs, 1), _wallHighlight);
    }
    // Bottom edge.
    if (y < PacManGame.mazeH - 1 && game._maze[y + 1][x] != PacManGame.tWall) {
      canvas.drawRect(Rect.fromLTWH(px, py + cs - 1, cs, 1), _wallHighlight);
    }
    // Left edge.
    if (x > 0 && game._maze[y][x - 1] != PacManGame.tWall) {
      canvas.drawRect(Rect.fromLTWH(px, py, 1, cs), _wallHighlight);
    }
    // Right edge.
    if (x < PacManGame.mazeW - 1 && game._maze[y][x + 1] != PacManGame.tWall) {
      canvas.drawRect(Rect.fromLTWH(px + cs - 1, py, 1, cs), _wallHighlight);
    }
  }
}

// ---------------------------------------------------------------------------
// Pellet renderer: draws small dots and power pellets
// ---------------------------------------------------------------------------

class _PelletRenderer extends PositionComponent {
  _PelletRenderer({required this.game});

  final PacManGame game;

  final Paint _pelletPaint = Paint()..color = Pico8Palette.lightPeach;
  final Paint _powerPaint = Paint()..color = Pico8Palette.yellow;

  double _powerPulse = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _powerPulse += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = PacManGame.cellSize;
    const ox = PacManGame.mazeOffsetX;
    const oy = PacManGame.mazeOffsetY;

    final powerVisible = (sin(_powerPulse * 6) > -0.3);

    for (int y = 0; y < PacManGame.mazeH; y++) {
      for (int x = 0; x < PacManGame.mazeW; x++) {
        final tile = game._maze[y][x];
        final px = (x + ox) * cs;
        final py = (y + oy) * cs;

        if (tile == PacManGame.tPellet) {
          // Small 2×2 dot centered in the cell.
          canvas.drawRect(
            Rect.fromLTWH(px + 3.0, py + 3.0, 2, 2),
            _pelletPaint,
          );
        } else if (tile == PacManGame.tPower && powerVisible) {
          // Larger 4×4 pulsing dot.
          canvas.drawRect(
            Rect.fromLTWH(px + 2.0, py + 2.0, 4, 4),
            _powerPaint,
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Pac-Man renderer: yellow circle with animated mouth
// ---------------------------------------------------------------------------

class _PacManRenderer extends PositionComponent {
  _PacManRenderer({required this.game});

  final PacManGame game;

  final Paint _pacPaint = Paint()..color = Pico8Palette.yellow;

  @override
  int get priority => 10;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = PacManGame.cellSize;
    const ox = PacManGame.mazeOffsetX;
    const oy = PacManGame.mazeOffsetY;

    final pos = game._pacPos;
    final centerX = (pos.x + ox) * cs + cs / 2.0;
    final centerY = (pos.y + oy) * cs + cs / 2.0;
    final radius = cs / 2.0;

    // Calculate mouth opening angle (0 to ~45 degrees).
    final mouthAngle = game._pacMouthAngle * 0.7; // ~40 degrees max

    // Determine rotation based on direction.
    double rotation = 0;
    final dir = game._pacDir;
    if (dir.x == 1) rotation = 0;
    if (dir.x == -1) rotation = pi;
    if (dir.y == -1) rotation = -pi / 2;
    if (dir.y == 1) rotation = pi / 2;

    // Draw Pac-Man as a filled arc (circle minus mouth wedge).
    final startAngle = rotation + mouthAngle;
    final sweepAngle = 2 * pi - 2 * mouthAngle;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      startAngle,
      sweepAngle,
      true,
      _pacPaint,
    );

    // Eye – small dark pixel.
    final eyeX = centerX + cos(rotation - 0.8) * (radius * 0.4);
    final eyeY = centerY + sin(rotation - 0.8) * (radius * 0.4);
    canvas.drawRect(
      Rect.fromLTWH(eyeX, eyeY, 1, 1),
      Paint()..color = Pico8Palette.black,
    );
  }
}

// ---------------------------------------------------------------------------
// Ghost renderer: draws all four ghosts
// ---------------------------------------------------------------------------

class _GhostRenderer extends PositionComponent {
  _GhostRenderer({required this.game});

  final PacManGame game;

  final Paint _frightenedPaint = Paint()..color = Pico8Palette.darkBlue;
  final Paint _frightenedFlashPaint = Paint()..color = Pico8Palette.white;
  final Paint _eyeWhitePaint = Paint()..color = Pico8Palette.white;
  final Paint _eyePupilPaint = Paint()..color = Pico8Palette.darkBlue;


  double _flashTimer = 0;

  @override
  int get priority => 10;

  @override
  void update(double dt) {
    super.update(dt);
    _flashTimer += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    const cs = PacManGame.cellSize;
    const ox = PacManGame.mazeOffsetX;
    const oy = PacManGame.mazeOffsetY;

    for (final g in game._ghosts) {
      if (g.state == _GhostState.home) continue;

      final px = (g.pos.x + ox) * cs;
      final py = (g.pos.y + oy) * cs;

      if (g.state == _GhostState.eaten) {
        // Just eyes floating back.
        _drawEyes(canvas, px.toDouble(), py.toDouble(), g.dir);
        continue;
      }

      // Ghost body color.
      Paint bodyPaint;
      if (g.state == _GhostState.frightened) {
        // Flash white when frightened timer is low.
        final flashing = game._frightenedTimer < 2.0 &&
            ((_flashTimer * 8).floor() % 2 == 0);
        bodyPaint = flashing ? _frightenedFlashPaint : _frightenedPaint;
      } else {
        bodyPaint = Paint()..color = g.color;
      }

      // Ghost body: rounded top, wavy bottom.
      // Top half (rounded rectangle).
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          px.toDouble(),
          py.toDouble(),
          px + cs.toDouble(),
          py + cs.toDouble() - 2,
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        bodyPaint,
      );

      // Bottom part with "feet" (3 small bumps).
      canvas.drawRect(
        Rect.fromLTWH(px.toDouble(), py + cs - 4.0, cs.toDouble(), 2),
        bodyPaint,
      );
      // Three "feet".
      for (int f = 0; f < 3; f++) {
        final fx = px + f * 3.0;
        canvas.drawRect(
          Rect.fromLTWH(fx, py + cs - 2.0, 2, 2),
          bodyPaint,
        );
      }

      // Eyes (unless frightened).
      if (g.state != _GhostState.frightened) {
        _drawEyes(canvas, px.toDouble(), py.toDouble(), g.dir);
      } else {
        // Frightened face: simple expression.
        // Small eyes.
        canvas.drawRect(
          Rect.fromLTWH(px + 2.0, py + 2.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 5.0, py + 2.0, 1, 1),
          _eyeWhitePaint,
        );
        // Wavy mouth.
        canvas.drawRect(
          Rect.fromLTWH(px + 1.0, py + 5.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 2.0, py + 4.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 3.0, py + 5.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 4.0, py + 4.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 5.0, py + 5.0, 1, 1),
          _eyeWhitePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(px + 6.0, py + 4.0, 1, 1),
          _eyeWhitePaint,
        );
      }
    }
  }

  void _drawEyes(Canvas canvas, double px, double py, Point<int> dir) {
    // Two white eye backgrounds.
    canvas.drawRect(Rect.fromLTWH(px + 1, py + 1, 3, 3), _eyeWhitePaint);
    canvas.drawRect(Rect.fromLTWH(px + 5, py + 1, 3, 3), _eyeWhitePaint);

    // Pupil offset based on direction.
    double pdx = 0, pdy = 0;
    if (dir.x > 0) pdx = 1;
    if (dir.x < 0) pdx = -1;
    if (dir.y > 0) pdy = 1;
    if (dir.y < 0) pdy = -1;

    canvas.drawRect(
      Rect.fromLTWH(px + 2 + pdx, py + 2 + pdy, 1, 1),
      _eyePupilPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(px + 6 + pdx, py + 2 + pdy, 1, 1),
      _eyePupilPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Fruit renderer
// ---------------------------------------------------------------------------

class _FruitRenderer extends PositionComponent {
  _FruitRenderer({required this.game});

  final PacManGame game;

  final Paint _fruitPaint = Paint()..color = Pico8Palette.red;
  final Paint _stemPaint = Paint()..color = Pico8Palette.darkGreen;
  final Paint _highlightPaint = Paint()..color = Pico8Palette.pink;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!game._fruitActive) return;

    const cs = PacManGame.cellSize;
    const ox = PacManGame.mazeOffsetX;
    const oy = PacManGame.mazeOffsetY;

    final pos = game._fruitPos;
    final px = (pos.x + ox) * cs;
    final py = (pos.y + oy) * cs;

    // Cherry-style fruit.
    canvas.drawRect(
      Rect.fromLTWH(px + 2.0, py + 3.0, 4, 4),
      _fruitPaint,
    );
    // Stem.
    canvas.drawRect(
      Rect.fromLTWH(px + 3.0, py + 1.0, 1, 2),
      _stemPaint,
    );
    // Highlight.
    canvas.drawRect(
      Rect.fromLTWH(px + 3.0, py + 3.0, 1, 1),
      _highlightPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Ready overlay: full-screen start screen with pixel art and animations
// ---------------------------------------------------------------------------

class _ReadyOverlay extends PositionComponent {
  _ReadyOverlay({required this.game});

  final PacManGame game;

  // Text paints.
  late final TextPaint _readyPaint;
  late final TextPaint _tapPaint;
  late final TextPaint _creditPaint;

  // Paints for decorative elements.
  final Paint _bgPaint = Paint()..color = Pico8Palette.black.withValues(alpha: 0.92);
  final Paint _borderPaint1 = Paint()..color = Pico8Palette.blue;
  final Paint _borderPaint2 = Paint()..color = Pico8Palette.darkBlue;
  final Paint _pacPaint = Paint()..color = Pico8Palette.yellow;
  final Paint _pelletPaint = Paint()..color = Pico8Palette.lightPeach;

  // Ghost colors for the parade.
  static const List<Color> _ghostColors = [
    Pico8Palette.red,
    Pico8Palette.pink,
    Pico8Palette.blue,
    Pico8Palette.orange,
  ];

  double _timer = 0;

  // Animated Pac-Man chase position (loops across the screen).
  static const double _chaseSpeed = 40.0;
  static const double _chaseY = 148.0;

  // Title color cycling through PICO-8 palette.
  static const List<Color> _titleColors = [
    Pico8Palette.yellow,
    Pico8Palette.orange,
    Pico8Palette.red,
    Pico8Palette.pink,
    Pico8Palette.lavender,
    Pico8Palette.blue,
    Pico8Palette.green,
    Pico8Palette.yellow,
  ];

  @override
  int get priority => 50;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _readyPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 8,
        fontFamily: 'monospace',
      ),
    );
    _tapPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 6,
        fontFamily: 'monospace',
      ),
    );
    _creditPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.darkGrey,
        fontSize: 5,
        fontFamily: 'monospace',
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!game._waitingToStart) return;

    const w = 256.0;
    const h = 240.0;

    // Full-screen dark backdrop.
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), _bgPaint);

    // --- Decorative pixel border (checkerboard) ---
    _drawPixelBorder(canvas, w, h);

    // --- Color-cycling "PAC-MAN" title ---
    _drawTitle(canvas, w);

    // --- Animated ghost chase scene ---
    _drawChaseScene(canvas, w);

    // --- Score legend ---
    _drawScoreLegend(canvas, w);

    // --- "READY!" text (pulsing) ---
    final readyScale = 1.0 + sin(_timer * 4) * 0.08;
    canvas.save();
    canvas.translate(w / 2, 186);
    canvas.scale(readyScale, readyScale);
    _readyPaint.render(canvas, 'READY!', Vector2(-20, -4));
    canvas.restore();

    // --- Blinking "TAP TO START" ---
    if (sin(_timer * 5) > -0.3) {
      _tapPaint.render(canvas, 'TAP TO START', Vector2(w / 2 - 30, 202));
    }

    // --- CRT scanlines ---
    _drawScanlines(canvas, w, h);

    // --- Bottom credit ---
    _creditPaint.render(canvas, 'PIXEL ARCADE', Vector2(w / 2 - 26, 226));
  }

  void _drawPixelBorder(Canvas canvas, double w, double h) {
    const ps = 4.0; // pixel size
    const thickness = 2; // border thickness in pixels

    for (double x = 0; x < w; x += ps) {
      for (double y = 0; y < h; y += ps) {
        final inBorder = y < ps * thickness ||
            y >= h - ps * thickness ||
            x < ps * thickness ||
            x >= w - ps * thickness;
        if (!inBorder) continue;

        final ix = (x / ps).floor();
        final iy = (y / ps).floor();
        final paint = (ix + iy) % 2 == 0 ? _borderPaint1 : _borderPaint2;
        canvas.drawRect(Rect.fromLTWH(x, y, ps, ps), paint);
      }
    }
  }

  void _drawTitle(Canvas canvas, double w) {
    // Draw "PAC-MAN" with per-character color cycling.
    const title = 'PAC-MAN';
    const charW = 14.0; // approximate width per character at fontSize 12
    final startX = (w - title.length * charW) / 2;
    const y = 40.0;

    for (int i = 0; i < title.length; i++) {
      final colorIdx =
          ((i + (_timer * 3).floor()) % _titleColors.length).toInt();
      final paint = TextPaint(
        style: TextStyle(
          color: _titleColors[colorIdx],
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      );
      paint.render(canvas, title[i], Vector2(startX + i * charW, y));
    }

    // Decorative line under title.
    canvas.drawRect(
      Rect.fromLTWH(32, 58, w - 64, 1),
      Paint()..color = Pico8Palette.darkBlue,
    );
  }

  void _drawChaseScene(Canvas canvas, double w) {
    // Animated scene: Pac-Man chasing frightened ghosts across the screen.
    final baseX = (_timer * _chaseSpeed) % (w + 80) - 40;
    const y = _chaseY;

    // Draw pellet dots along the chase path.
    for (double px = 16; px < w - 16; px += 12) {
      canvas.drawRect(
        Rect.fromLTWH(px, y + 3, 2, 2),
        _pelletPaint,
      );
    }

    // Draw 4 frightened ghosts (ahead of Pac-Man).
    for (int i = 0; i < 4; i++) {
      final gx = baseX + 14 + i * 12.0;
      _drawMiniGhost(canvas, gx, y, _ghostColors[i], frightened: true);
    }

    // Draw Pac-Man (behind the ghosts, chasing).
    _drawMiniPacMan(canvas, baseX, y);
  }

  void _drawMiniPacMan(Canvas canvas, double x, double y) {
    // 8×8 pixel Pac-Man with animated mouth.
    final mouthOpen = sin(_timer * 12) > 0;
    final cx = x + 4;
    final cy = y + 4;

    if (mouthOpen) {
      // Open mouth: draw arc.
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: 4),
        0.4,
        2 * pi - 0.8,
        true,
        _pacPaint,
      );
    } else {
      // Closed mouth: full circle.
      canvas.drawCircle(Offset(cx, cy), 4, _pacPaint);
    }
  }

  void _drawMiniGhost(
    Canvas canvas,
    double x,
    double y,
    Color color, {
    bool frightened = false,
  }) {
    final bodyPaint = Paint()
      ..color = frightened ? Pico8Palette.darkBlue : color;
    final eyePaint = Paint()..color = Pico8Palette.white;

    // Body: rounded top rectangle + wavy bottom.
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        x, y, x + 8, y + 6,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      bodyPaint,
    );
    // Feet.
    canvas.drawRect(Rect.fromLTWH(x, y + 6, 2, 2), bodyPaint);
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 6, 2, 2), bodyPaint);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 6, 2, 2), bodyPaint);

    if (frightened) {
      // Frightened face: small dots for eyes, wavy mouth.
      canvas.drawRect(Rect.fromLTWH(x + 2, y + 2, 1, 1), eyePaint);
      canvas.drawRect(Rect.fromLTWH(x + 5, y + 2, 1, 1), eyePaint);
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 5, 1, 1), eyePaint);
      canvas.drawRect(Rect.fromLTWH(x + 3, y + 4, 1, 1), eyePaint);
      canvas.drawRect(Rect.fromLTWH(x + 5, y + 5, 1, 1), eyePaint);
    } else {
      // Normal eyes.
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 2, 2), eyePaint);
      canvas.drawRect(Rect.fromLTWH(x + 5, y + 2, 2, 2), eyePaint);
      final pupilPaint = Paint()..color = Pico8Palette.darkBlue;
      canvas.drawRect(Rect.fromLTWH(x + 2, y + 3, 1, 1), pupilPaint);
      canvas.drawRect(Rect.fromLTWH(x + 6, y + 3, 1, 1), pupilPaint);
    }
  }

  void _drawScoreLegend(Canvas canvas, double w) {
    // Show ghost characters with their names and point values.
    const startY = 72.0;
    const names = ['BLINKY', 'PINKY', 'INKY', 'CLYDE'];
    const points = ['200', '400', '800', '1600'];

    for (int i = 0; i < 4; i++) {
      final y = startY + i * 16.0;

      // Ghost icon.
      _drawMiniGhost(canvas, 50, y, _ghostColors[i]);

      // Name.
      final namePaint = TextPaint(
        style: TextStyle(
          color: _ghostColors[i],
          fontSize: 6,
          fontFamily: 'monospace',
        ),
      );
      namePaint.render(canvas, names[i], Vector2(66, y + 2));

      // Dash and points.
      final ptsPaint = TextPaint(
        style: TextStyle(
          color: Pico8Palette.white,
          fontSize: 6,
          fontFamily: 'monospace',
        ),
      );
      ptsPaint.render(canvas, '- ${points[i]} PTS', Vector2(120, y + 2));
    }

    // Power pellet legend.
    final powerPulse = sin(_timer * 6) > -0.3;
    if (powerPulse) {
      canvas.drawRect(
        Rect.fromLTWH(50, startY + 68, 6, 6),
        Paint()..color = Pico8Palette.yellow,
      );
    }
    final legendPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.yellow,
        fontSize: 6,
        fontFamily: 'monospace',
      ),
    );
    legendPaint.render(
      canvas,
      'POWER PELLET',
      Vector2(66, startY + 70),
    );
  }

  void _drawScanlines(Canvas canvas, double w, double h) {
    final paint = Paint()..color = Pico8Palette.black.withValues(alpha: 0.06);
    for (double y = 0; y < h; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 2), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// HUD: score, lives, and level
// ---------------------------------------------------------------------------

class _HudComponent extends PositionComponent {
  _HudComponent({required this.game});

  final PacManGame game;

  late final TextPaint _textPaint;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _textPaint = TextPaint(
      style: TextStyle(
        color: Pico8Palette.white,
        fontSize: 7,
        fontFamily: 'monospace',
      ),
    );
  }

  @override
  int get priority => 20;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Score at top-left in the border area.
    _textPaint.render(canvas, 'SCORE:${game.score}', Vector2(4, 1));
    // Lives at top-right.
    _textPaint.render(canvas, 'L:${game.lives}', Vector2(200, 1));
    // Level indicator.
    _textPaint.render(canvas, 'LV${game._level}', Vector2(240, 1));
  }
}
