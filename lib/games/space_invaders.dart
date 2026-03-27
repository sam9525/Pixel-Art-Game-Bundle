import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../core/base_game.dart';
import '../core/palette.dart';
import '../shared/game_components.dart';

// ---------------------------------------------------------------------------
// Alien type definitions
// ---------------------------------------------------------------------------

enum _AlienType { squid, crab, octopus }

enum _GameState { playing, dying, gameOver }

// ---------------------------------------------------------------------------
// Classic Space Invaders arcade game with pixel-art aesthetics.
//
// Destroy waves of descending aliens with your ship. Drag to move,
// tap to fire. Shields provide destructible cover. A mystery UFO
// occasionally flies across the top for bonus points.
// ---------------------------------------------------------------------------

class SpaceInvadersGame extends BaseArcadeGame
    with DragCallbacks, TapCallbacks {
  SpaceInvadersGame() : super(gameId: 'space_invaders');

  // --- Layout constants ---
  static const double _hudHeight = 16.0;
  static const double _playTop = 16.0;
  static const double _playBottom = 224.0;
  static const double _playerY = 216.0;
  static const double _playerW = 12.0;
  static const double _playerH = 8.0;
  static const double _playerMinX = 8.0;
  static const double _playerMaxX = 244.0;

  static const int _gridCols = 11;
  static const int _gridRows = 5;
  static const double _alienW = 10.0;
  static const double _alienH = 8.0;
  static const double _alienSpacingX = 16.0;
  static const double _alienSpacingY = 14.0;
  static const double _gridStartX = 20.0;
  static const double _gridStartY = 36.0;

  static const double _bulletW = 2.0;
  static const double _bulletH = 6.0;
  static const double _playerBulletSpeed = 200.0;
  static const double _alienBulletSpeed = 100.0;
  static const int _maxPlayerBullets = 2;
  static const int _maxAlienBullets = 3;

  static const double _baseAlienSpeed = 30.0;
  static const double _maxAlienSpeed = 120.0;
  static const double _alienDropAmount = 8.0;
  static const double _alienAnimInterval = 0.6;

  static const double _ufoY = 22.0;
  static const double _ufoW = 12.0;
  static const double _ufoH = 6.0;
  static const double _ufoSpeed = 60.0;
  static const double _ufoMinInterval = 15.0;
  static const double _ufoMaxInterval = 25.0;

  static const double _shieldY = 190.0;
  static const int _shieldW = 20;
  static const int _shieldH = 14;
  static const int _shieldCount = 4;
  static const int _shieldDamageRadius = 1; // 3x3 chunk = radius 1

  static const double _invulnDuration = 1.5;
  static const double _alienFireMinInterval = 0.6;
  static const double _alienFireMaxInterval = 1.4;

  static const List<int> _alienRowPoints = [30, 20, 20, 10, 10];
  static const List<_AlienType> _alienRowTypes = [
    _AlienType.squid,
    _AlienType.crab,
    _AlienType.crab,
    _AlienType.octopus,
    _AlienType.octopus,
  ];
  static const List<int> _ufoPointValues = [50, 100, 150, 300];

  final Random _rng = Random();

  // --- Game state ---
  _GameState _gameState = _GameState.playing;
  int _wave = 0;

  // Alien grid data.
  final List<_AlienData> _aliens = [];
  final Vector2 _alienGridPos = Vector2.zero();
  int _alienDir = 1; // 1 = right, -1 = left
  double _alienSpeed = _baseAlienSpeed;
  int _alienAnimFrame = 0;
  double _alienAnimTimer = 0.0;

  // Player.
  double _playerX = 128.0;
  final List<Vector2> _playerBullets = [];

  // Alien bullets.
  final List<Vector2> _alienBullets = [];
  double _alienFireTimer = 0.0;

  // Shields: list of 2D boolean grids. true = pixel present.
  final List<List<List<bool>>> _shields = [];
  final List<double> _shieldXPositions = [];

  // UFO.
  bool _ufoActive = false;
  double _ufoX = 0.0;
  int _ufoDir = 1;
  int _ufoPoints = 100;
  double _ufoTimer = 0.0;

  // Invulnerability.
  bool _invulnerable = false;
  double _invulnTimer = 0.0;

  // Effect components.
  late SharedScreenFlash _screenFlash;

  @override
  Color backgroundColor() => Pico8Palette.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final res = BaseArcadeGame.resolution;
    _screenFlash = SharedScreenFlash(size: res.clone());

    world.addAll([
      _BackgroundRenderer(),
      _ShieldRenderer(game: this),
      _AlienRenderer(game: this),
      _PlayerRenderer(game: this),
      _BulletRenderer(game: this),
      _UfoRenderer(game: this),
      _screenFlash,
      SharedHudComponent(game: this, scorePosition: Vector2(4, 4), livesPosition: Vector2(180, 4)),
    ]);

    _initGame();
  }

  // --- Initialization ---

  void _initGame() {
    _wave = 0;
    _gameState = _GameState.playing;
    _playerX = 128.0;
    _playerBullets.clear();
    _alienBullets.clear();
    _invulnerable = false;
    _invulnTimer = 0.0;
    _ufoActive = false;
    _ufoTimer = _ufoMinInterval + _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
    _alienFireTimer = _alienFireMinInterval + _rng.nextDouble() * (_alienFireMaxInterval - _alienFireMinInterval);

    _initAliens();
    _initShields();
  }

  void _initAliens() {
    _aliens.clear();
    for (int row = 0; row < _gridRows; row++) {
      for (int col = 0; col < _gridCols; col++) {
        _aliens.add(_AlienData(
          gridCol: col,
          gridRow: row,
          type: _alienRowTypes[row],
          points: _alienRowPoints[row],
          alive: true,
        ));
      }
    }
    _alienGridPos.setValues(_gridStartX, _gridStartY);
    _alienDir = 1;
    _alienSpeed = _baseAlienSpeed * pow(1.1, _wave);
    _alienAnimFrame = 0;
    _alienAnimTimer = 0.0;
  }

  void _initShields() {
    _shields.clear();
    _shieldXPositions.clear();
    final res = BaseArcadeGame.resolution;
    // Evenly space 4 shields across the screen.
    final totalShieldWidth = _shieldCount * _shieldW;
    final spacing = (res.x - totalShieldWidth) / (_shieldCount + 1);

    for (int i = 0; i < _shieldCount; i++) {
      final x = spacing + i * (spacing + _shieldW);
      _shieldXPositions.add(x);
      // Create a 2D boolean grid with a classic bunker shape.
      final grid = List.generate(
        _shieldH,
        (row) => List.generate(_shieldW, (col) {
          // Create an arch shape: full rectangle with rounded top
          // and a notch cut from the bottom center.
          // Rounded top corners.
          if (row == 0 && (col < 2 || col >= _shieldW - 2)) return false;
          if (row == 1 && (col < 1 || col >= _shieldW - 1)) return false;
          // Bottom center notch.
          if (row >= _shieldH - 4 && col >= _shieldW ~/ 2 - 3 && col < _shieldW ~/ 2 + 3) {
            return false;
          }
          if (row >= _shieldH - 3 && col >= _shieldW ~/ 2 - 2 && col < _shieldW ~/ 2 + 2) {
            return false;
          }
          return true;
        }),
      );
      _shields.add(grid);
    }
  }

  // --- Helpers ---

  int get _aliveAlienCount => _aliens.where((a) => a.alive).length;

  /// Get the world position of an alien given its grid coordinates.
  Vector2 _alienWorldPos(_AlienData alien) {
    return Vector2(
      _alienGridPos.x + alien.gridCol * _alienSpacingX,
      _alienGridPos.y + alien.gridRow * _alienSpacingY,
    );
  }

  /// Find the lowest alive alien in each column (candidates to fire).
  List<_AlienData> _bottomAliens() {
    final Map<int, _AlienData> bottom = {};
    for (final alien in _aliens) {
      if (!alien.alive) continue;
      final existing = bottom[alien.gridCol];
      if (existing == null || alien.gridRow > existing.gridRow) {
        bottom[alien.gridCol] = alien;
      }
    }
    return bottom.values.toList();
  }

  // --- Update loop ---

  @override
  void update(double dt) {
    super.update(dt);

    if (_gameState == _GameState.gameOver) return;

    // Handle invulnerability timer even during dying state.
    if (_invulnerable) {
      _invulnTimer -= dt;
      if (_invulnTimer <= 0) {
        _invulnerable = false;
        _invulnTimer = 0.0;
        if (_gameState == _GameState.dying) {
          _gameState = _GameState.playing;
        }
      }
    }

    if (_gameState == _GameState.dying) return;

    _updateAliens(dt);
    _updatePlayerBullets(dt);
    _updateAlienBullets(dt);
    _updateAlienFiring(dt);
    _updateUfo(dt);
    _checkCollisions();
    _checkAlienReachedBottom();
    _checkWaveClear();
  }

  void _updateAliens(double dt) {
    final aliveCount = _aliveAlienCount;
    if (aliveCount == 0) return;

    // Speed scales inversely with remaining aliens.
    final speedMultiplier = (55.0 / aliveCount).clamp(1.0, _maxAlienSpeed / _alienSpeed);
    final effectiveSpeed = (_alienSpeed * speedMultiplier).clamp(0.0, _maxAlienSpeed);

    // Animation frame toggle.
    _alienAnimTimer += dt;
    if (_alienAnimTimer >= _alienAnimInterval) {
      _alienAnimTimer -= _alienAnimInterval;
      _alienAnimFrame = (_alienAnimFrame + 1) % 2;
    }

    // Move the grid horizontally.
    _alienGridPos.x += _alienDir * effectiveSpeed * dt;

    // Check if any alive alien has hit an edge.
    bool hitEdge = false;
    for (final alien in _aliens) {
      if (!alien.alive) continue;
      final pos = _alienWorldPos(alien);
      if (pos.x < 8 || pos.x + _alienW > 248) {
        hitEdge = true;
        break;
      }
    }

    if (hitEdge) {
      _alienDir = -_alienDir;
      _alienGridPos.y += _alienDropAmount;
      // Correct the horizontal overshoot.
      _alienGridPos.x += _alienDir * effectiveSpeed * dt;
    }
  }

  void _updatePlayerBullets(double dt) {
    for (int i = _playerBullets.length - 1; i >= 0; i--) {
      _playerBullets[i].y -= _playerBulletSpeed * dt;
      if (_playerBullets[i].y < _playTop - _bulletH) {
        _playerBullets.removeAt(i);
      }
    }
  }

  void _updateAlienBullets(double dt) {
    for (int i = _alienBullets.length - 1; i >= 0; i--) {
      _alienBullets[i].y += _alienBulletSpeed * dt;
      if (_alienBullets[i].y > _playBottom + _bulletH) {
        _alienBullets.removeAt(i);
      }
    }
  }

  void _updateAlienFiring(double dt) {
    _alienFireTimer -= dt;
    if (_alienFireTimer <= 0) {
      _alienFireTimer = _alienFireMinInterval +
          _rng.nextDouble() * (_alienFireMaxInterval - _alienFireMinInterval);

      if (_alienBullets.length < _maxAlienBullets) {
        final candidates = _bottomAliens();
        if (candidates.isNotEmpty) {
          final shooter = candidates[_rng.nextInt(candidates.length)];
          final pos = _alienWorldPos(shooter);
          _alienBullets.add(Vector2(
            pos.x + _alienW / 2 - _bulletW / 2,
            pos.y + _alienH,
          ));
        }
      }
    }
  }

  void _updateUfo(double dt) {
    if (_ufoActive) {
      _ufoX += _ufoDir * _ufoSpeed * dt;
      if (_ufoX < -_ufoW || _ufoX > 256 + _ufoW) {
        _ufoActive = false;
        _ufoTimer = _ufoMinInterval +
            _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
      }
    } else {
      _ufoTimer -= dt;
      if (_ufoTimer <= 0) {
        _ufoActive = true;
        _ufoDir = _rng.nextBool() ? 1 : -1;
        _ufoX = _ufoDir == 1 ? -_ufoW : 256 + _ufoW;
        _ufoPoints = _ufoPointValues[_rng.nextInt(_ufoPointValues.length)];
      }
    }
  }

  // --- Collision detection (manual AABB) ---

  void _checkCollisions() {
    _checkPlayerBulletsVsAliens();
    _checkPlayerBulletsVsShields();
    _checkPlayerBulletsVsUfo();
    _checkAlienBulletsVsPlayer();
    _checkAlienBulletsVsShields();
  }

  void _checkPlayerBulletsVsAliens() {
    for (int bi = _playerBullets.length - 1; bi >= 0; bi--) {
      final bullet = _playerBullets[bi];
      final bulletRect = Rect.fromLTWH(bullet.x, bullet.y, _bulletW, _bulletH);
      bool hit = false;

      for (final alien in _aliens) {
        if (!alien.alive) continue;
        final pos = _alienWorldPos(alien);
        final alienRect = Rect.fromLTWH(pos.x, pos.y, _alienW, _alienH);

        if (bulletRect.overlaps(alienRect)) {
          alien.alive = false;
          score += alien.points;

          // Spawn score popup.
          world.add(SharedScorePopup(
            position: Vector2(pos.x + _alienW / 2, pos.y),
            points: alien.points,
          ));

          // Spawn explosion flash.
          world.add(_ExplosionFlash(
            rect: alienRect,
          ));

          _playerBullets.removeAt(bi);
          hit = true;
          break;
        }
      }
      if (hit) continue;
    }
  }

  void _checkPlayerBulletsVsShields() {
    for (int bi = _playerBullets.length - 1; bi >= 0; bi--) {
      final bullet = _playerBullets[bi];
      if (_damageShield(bullet.x, bullet.y, _bulletW, _bulletH)) {
        _playerBullets.removeAt(bi);
      }
    }
  }

  void _checkPlayerBulletsVsUfo() {
    if (!_ufoActive) return;
    for (int bi = _playerBullets.length - 1; bi >= 0; bi--) {
      final bullet = _playerBullets[bi];
      final bulletRect = Rect.fromLTWH(bullet.x, bullet.y, _bulletW, _bulletH);
      final ufoRect = Rect.fromLTWH(_ufoX, _ufoY, _ufoW, _ufoH);

      if (bulletRect.overlaps(ufoRect)) {
        score += _ufoPoints;
        world.add(SharedScorePopup(
          position: Vector2(_ufoX + _ufoW / 2, _ufoY),
          points: _ufoPoints,
        ));
        world.add(_ExplosionFlash(
          rect: ufoRect,
        ));
        _ufoActive = false;
        _ufoTimer = _ufoMinInterval +
            _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
        _playerBullets.removeAt(bi);
        break;
      }
    }
  }

  void _checkAlienBulletsVsPlayer() {
    if (_invulnerable) return;
    final playerRect = Rect.fromLTWH(
      _playerX - _playerW / 2,
      _playerY - _playerH / 2,
      _playerW,
      _playerH,
    );

    for (int bi = _alienBullets.length - 1; bi >= 0; bi--) {
      final bullet = _alienBullets[bi];
      final bulletRect = Rect.fromLTWH(bullet.x, bullet.y, _bulletW, _bulletH);

      if (bulletRect.overlaps(playerRect)) {
        _alienBullets.removeAt(bi);
        _hitPlayer();
        return;
      }
    }
  }

  void _checkAlienBulletsVsShields() {
    for (int bi = _alienBullets.length - 1; bi >= 0; bi--) {
      final bullet = _alienBullets[bi];
      if (_damageShield(bullet.x, bullet.y, _bulletW, _bulletH)) {
        _alienBullets.removeAt(bi);
      }
    }
  }

  /// Check if a rectangle overlaps any shield pixel and damage it.
  /// Returns true if a hit occurred.
  bool _damageShield(double bx, double by, double bw, double bh) {
    final bulletRect = Rect.fromLTWH(bx, by, bw, bh);

    for (int si = 0; si < _shields.length; si++) {
      final sx = _shieldXPositions[si];
      final shieldRect = Rect.fromLTWH(sx, _shieldY, _shieldW.toDouble(), _shieldH.toDouble());

      if (!bulletRect.overlaps(shieldRect)) continue;

      // Check individual pixels.
      final grid = _shields[si];
      // Find the pixel coordinate of the hit center relative to the shield.
      final hitCenterX = (bx + bw / 2 - sx).round().clamp(0, _shieldW - 1);
      final hitCenterY = (by + bh / 2 - _shieldY).round().clamp(0, _shieldH - 1);

      // Check if any pixel in the area is present.
      bool anyHit = false;
      for (int dy = -_shieldDamageRadius - 1; dy <= _shieldDamageRadius + 1; dy++) {
        for (int dx = -_shieldDamageRadius - 1; dx <= _shieldDamageRadius + 1; dx++) {
          final py = hitCenterY + dy;
          final px = hitCenterX + dx;
          if (py >= 0 && py < _shieldH && px >= 0 && px < _shieldW) {
            if (grid[py][px]) {
              anyHit = true;
            }
          }
        }
      }

      if (anyHit) {
        // Destroy a 3x3 chunk around the hit point.
        for (int dy = -_shieldDamageRadius; dy <= _shieldDamageRadius; dy++) {
          for (int dx = -_shieldDamageRadius; dx <= _shieldDamageRadius; dx++) {
            final py = hitCenterY + dy;
            final px = hitCenterX + dx;
            if (py >= 0 && py < _shieldH && px >= 0 && px < _shieldW) {
              grid[py][px] = false;
            }
          }
        }
        return true;
      }
    }
    return false;
  }

  void _hitPlayer() {
    lives -= 1;
    _screenFlash.trigger();

    if (lives <= 0) {
      _gameState = _GameState.gameOver;
      onGameOver();
    } else {
      _gameState = _GameState.dying;
      _invulnerable = true;
      _invulnTimer = _invulnDuration;
    }
  }

  void _checkAlienReachedBottom() {
    for (final alien in _aliens) {
      if (!alien.alive) continue;
      final pos = _alienWorldPos(alien);
      if (pos.y + _alienH > 208) {
        _gameState = _GameState.gameOver;
        onGameOver();
        return;
      }
    }
  }

  void _checkWaveClear() {
    if (_aliveAlienCount == 0) {
      _wave++;
      _playerBullets.clear();
      _alienBullets.clear();
      _initAliens();
      _initShields();
      _ufoActive = false;
      _ufoTimer = _ufoMinInterval +
          _rng.nextDouble() * (_ufoMaxInterval - _ufoMinInterval);
    }
  }

  // --- Input handling ---

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_gameState == _GameState.gameOver) return;
    _playerX += event.localDelta.x;
    _playerX = _playerX.clamp(_playerMinX, _playerMaxX);
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_gameState == _GameState.gameOver) return;
    if (_gameState == _GameState.dying) return;
    _firePlayerBullet();
  }

  void _firePlayerBullet() {
    if (_playerBullets.length >= _maxPlayerBullets) return;
    _playerBullets.add(Vector2(
      _playerX - _bulletW / 2,
      _playerY - _playerH / 2 - _bulletH,
    ));
  }

  // --- Game lifecycle ---

  @override
  void resetGame() {
    score = 0;
    lives = 3;
    _initGame();
  }

  @override
  void onGameOver() {
    _gameState = _GameState.gameOver;
    overlays.add('GameOver');
  }
}

// ---------------------------------------------------------------------------
// Alien data record
// ---------------------------------------------------------------------------

class _AlienData {
  _AlienData({
    required this.gridCol,
    required this.gridRow,
    required this.type,
    required this.points,
    required this.alive,
  });

  final int gridCol;
  final int gridRow;
  final _AlienType type;
  final int points;
  bool alive;
}

// ---------------------------------------------------------------------------
// Background renderer: dark blue with faint stars
// ---------------------------------------------------------------------------

class _BackgroundRenderer extends PositionComponent {
  final List<Offset> _stars = [];
  final List<double> _starBrightness = [];
  bool _initialized = false;

  void _initStars() {
    if (_initialized) return;
    _initialized = true;
    final rng = Random(42); // fixed seed for consistent star field
    final res = BaseArcadeGame.resolution;
    for (int i = 0; i < 40; i++) {
      _stars.add(Offset(
        rng.nextDouble() * res.x,
        SpaceInvadersGame._hudHeight + rng.nextDouble() * (res.y - SpaceInvadersGame._hudHeight),
      ));
      _starBrightness.add(0.15 + rng.nextDouble() * 0.25);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _initStars();

    final res = BaseArcadeGame.resolution;
    // Dark blue background below HUD.
    canvas.drawRect(
      Rect.fromLTWH(0, SpaceInvadersGame._hudHeight, res.x, res.y - SpaceInvadersGame._hudHeight),
      Paint()..color = Pico8Palette.darkBlue,
    );

    // Faint stars.
    for (int i = 0; i < _stars.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(_stars[i].dx, _stars[i].dy, 1, 1),
        Paint()..color = Pico8Palette.lightGrey.withValues(alpha: _starBrightness[i]),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Alien renderer: draws all alive aliens with animation frames
// ---------------------------------------------------------------------------

class _AlienRenderer extends PositionComponent {
  _AlienRenderer({required this.game});

  final SpaceInvadersGame game;

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final alien in game._aliens) {
      if (!alien.alive) continue;
      final pos = game._alienWorldPos(alien);
      _drawAlien(canvas, pos.x, pos.y, alien.type, game._alienAnimFrame);
    }
  }

  void _drawAlien(Canvas canvas, double x, double y, _AlienType type, int frame) {
    switch (type) {
      case _AlienType.squid:
        _drawSquid(canvas, x, y, frame);
      case _AlienType.crab:
        _drawCrab(canvas, x, y, frame);
      case _AlienType.octopus:
        _drawOctopus(canvas, x, y, frame);
    }
  }

  /// Squid alien (top row): lavender, 10x8 pixels.
  void _drawSquid(Canvas canvas, double x, double y, int frame) {
    _paint.color = Pico8Palette.lavender;

    // Body: central mass.
    canvas.drawRect(Rect.fromLTWH(x + 4, y, 2, 2), _paint); // top center
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, 4, 2), _paint); // upper body
    canvas.drawRect(Rect.fromLTWH(x + 2, y + 4, 6, 2), _paint); // mid body
    // Eyes.
    _paint.color = Pico8Palette.white;
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 4, 1, 1), _paint);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 4, 1, 1), _paint);
    // Tentacles.
    _paint.color = Pico8Palette.lavender;
    if (frame == 0) {
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 7, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 4, y + 6, 2, 1), _paint);
    } else {
      canvas.drawRect(Rect.fromLTWH(x + 2, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 6, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 4, y + 6, 2, 2), _paint);
    }
  }

  /// Crab alien (rows 1-2): blue, 10x8 pixels.
  void _drawCrab(Canvas canvas, double x, double y, int frame) {
    _paint.color = Pico8Palette.blue;

    // Body.
    canvas.drawRect(Rect.fromLTWH(x + 2, y, 6, 2), _paint); // top
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 8, 2), _paint); // mid
    canvas.drawRect(Rect.fromLTWH(x + 0, y + 4, 10, 2), _paint); // wide
    // Eyes.
    _paint.color = Pico8Palette.white;
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, 1, 1), _paint);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 2, 1, 1), _paint);
    // Claws/legs.
    _paint.color = Pico8Palette.blue;
    if (frame == 0) {
      canvas.drawRect(Rect.fromLTWH(x + 0, y + 6, 2, 1), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 8, y + 6, 2, 1), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 3, y + 6, 1, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 6, y + 6, 1, 2), _paint);
    } else {
      canvas.drawRect(Rect.fromLTWH(x + 0, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 8, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 3, y + 6, 1, 1), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 6, y + 6, 1, 1), _paint);
    }
  }

  /// Octopus alien (rows 3-4): green, 10x8 pixels.
  void _drawOctopus(Canvas canvas, double x, double y, int frame) {
    _paint.color = Pico8Palette.green;

    // Body.
    canvas.drawRect(Rect.fromLTWH(x + 3, y, 4, 2), _paint); // head
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 8, 2), _paint); // body
    canvas.drawRect(Rect.fromLTWH(x + 0, y + 4, 10, 2), _paint); // wide
    // Eyes.
    _paint.color = Pico8Palette.white;
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, 1, 1), _paint);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 2, 1, 1), _paint);
    // Tentacles.
    _paint.color = Pico8Palette.green;
    if (frame == 0) {
      canvas.drawRect(Rect.fromLTWH(x + 0, y + 6, 2, 1), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 3, y + 6, 1, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 6, y + 6, 1, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 8, y + 6, 2, 1), _paint);
    } else {
      canvas.drawRect(Rect.fromLTWH(x + 1, y + 6, 2, 2), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 4, y + 6, 2, 1), _paint);
      canvas.drawRect(Rect.fromLTWH(x + 7, y + 6, 2, 2), _paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Player renderer: draws the ship, blinks during invulnerability
// ---------------------------------------------------------------------------

class _PlayerRenderer extends PositionComponent {
  _PlayerRenderer({required this.game});

  final SpaceInvadersGame game;

  final Paint _bodyPaint = Paint()..color = Pico8Palette.green;
  final Paint _cockpitPaint = Paint()..color = Pico8Palette.white;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (game._gameState == _GameState.gameOver) return;

    // Blink during invulnerability: skip rendering on odd frames.
    if (game._invulnerable) {
      final blink = ((game._invulnTimer * 10).toInt()) % 2;
      if (blink == 1) return;
    }

    final cx = game._playerX;
    const cy = SpaceInvadersGame._playerY;
    const hw = SpaceInvadersGame._playerW / 2;
    const hh = SpaceInvadersGame._playerH / 2;

    // Ship body: a rectangle with a turret on top.
    // Main hull: 12x4 at bottom.
    canvas.drawRect(
      Rect.fromLTWH(cx - hw, cy - hh + 4, SpaceInvadersGame._playerW, 4),
      _bodyPaint,
    );
    // Upper hull: 8x2.
    canvas.drawRect(
      Rect.fromLTWH(cx - 4, cy - hh + 2, 8, 2),
      _bodyPaint,
    );
    // Turret: 2x2.
    canvas.drawRect(
      Rect.fromLTWH(cx - 1, cy - hh, 2, 2),
      _cockpitPaint,
    );
    // Cockpit highlight.
    canvas.drawRect(
      Rect.fromLTWH(cx - 3, cy - hh + 3, 2, 1),
      _cockpitPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 1, cy - hh + 3, 2, 1),
      _cockpitPaint,
    );
  }
}

// ---------------------------------------------------------------------------
// Bullet renderer: draws player and alien bullets
// ---------------------------------------------------------------------------

class _BulletRenderer extends PositionComponent {
  _BulletRenderer({required this.game});

  final SpaceInvadersGame game;

  final Paint _playerBulletPaint = Paint()..color = Pico8Palette.yellow;
  final Paint _alienBulletPaint = Paint()..color = Pico8Palette.red;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final b in game._playerBullets) {
      canvas.drawRect(
        Rect.fromLTWH(b.x, b.y, SpaceInvadersGame._bulletW, SpaceInvadersGame._bulletH),
        _playerBulletPaint,
      );
    }

    for (final b in game._alienBullets) {
      canvas.drawRect(
        Rect.fromLTWH(b.x, b.y, SpaceInvadersGame._bulletW, SpaceInvadersGame._bulletH),
        _alienBulletPaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Shield renderer: draws destructible shields from boolean grids
// ---------------------------------------------------------------------------

class _ShieldRenderer extends PositionComponent {
  _ShieldRenderer({required this.game});

  final SpaceInvadersGame game;

  final Paint _shieldPaint = Paint()..color = Pico8Palette.darkGreen;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (int si = 0; si < game._shields.length; si++) {
      final grid = game._shields[si];
      final sx = game._shieldXPositions[si];

      for (int row = 0; row < SpaceInvadersGame._shieldH; row++) {
        for (int col = 0; col < SpaceInvadersGame._shieldW; col++) {
          if (grid[row][col]) {
            canvas.drawRect(
              Rect.fromLTWH(sx + col, SpaceInvadersGame._shieldY + row, 1, 1),
              _shieldPaint,
            );
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// UFO renderer
// ---------------------------------------------------------------------------

class _UfoRenderer extends PositionComponent {
  _UfoRenderer({required this.game});

  final SpaceInvadersGame game;

  final Paint _bodyPaint = Paint()..color = Pico8Palette.red;
  final Paint _domePaint = Paint()..color = Pico8Palette.pink;
  final Paint _lightPaint = Paint()..color = Pico8Palette.yellow;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (!game._ufoActive) return;

    final x = game._ufoX;
    const y = SpaceInvadersGame._ufoY;

    // UFO body: elliptical shape using rects.
    canvas.drawRect(Rect.fromLTWH(x + 3, y, 6, 2), _domePaint); // dome
    canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 10, 2), _bodyPaint); // main body
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 4, 6, 2), _bodyPaint); // bottom
    // Lights.
    canvas.drawRect(Rect.fromLTWH(x + 2, y + 3, 1, 1), _lightPaint);
    canvas.drawRect(Rect.fromLTWH(x + 5, y + 3, 1, 1), _lightPaint);
    canvas.drawRect(Rect.fromLTWH(x + 9, y + 3, 1, 1), _lightPaint);
  }
}

// ---------------------------------------------------------------------------
// Explosion flash: brief white flash at destroyed entity position
// ---------------------------------------------------------------------------

class _ExplosionFlash extends PositionComponent {
  _ExplosionFlash({required this.rect});

  final Rect rect;

  static const double _lifetime = 0.12;
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
