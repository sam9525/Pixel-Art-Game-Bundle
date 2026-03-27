import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../core/base_game.dart';
import '../core/palette.dart';

// ---------------------------------------------------------------------------
// Shared screen flash on life loss
// ---------------------------------------------------------------------------

/// A full-screen flash overlay that briefly shows [color] when triggered.
/// Used by all games to indicate life loss.
class SharedScreenFlash extends RectangleComponent {
  SharedScreenFlash({
    Vector2? size,
    this.color = Pico8Palette.darkPurple,
    this.duration = 0.15,
  }) : super(
          position: Vector2.zero(),
          size: size ?? BaseArcadeGame.resolution.clone(),
          paint: Paint()..color = color,
          priority: 100,
        );

  final Color color;
  final double duration;

  double _timer = 0;
  bool _active = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint.color = color.withValues(alpha: 0);
  }

  /// Trigger a brief screen flash.
  void trigger() {
    _active = true;
    _timer = duration;
    paint.color = color;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_active) {
      _timer -= dt;
      if (_timer <= 0) {
        _active = false;
        paint.color = color.withValues(alpha: 0);
      } else {
        final opacity = (_timer / duration).clamp(0.0, 1.0);
        paint.color = color.withValues(alpha: opacity);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Shared floating score popup
// ---------------------------------------------------------------------------

/// A floating "+N" text that drifts upward and fades out.
/// Used by all games when scoring points.
class SharedScorePopup extends PositionComponent {
  SharedScorePopup({
    required super.position,
    this.points = 10,
    this.text = '+',
    this.lifetime = 0.6,
    this.driftSpeed = 35.0,
    this.fontSize = 7,
    this.color = Pico8Palette.yellow,
  }) : super();

  final int points;
  final String text;
  final double lifetime;
  final double driftSpeed;
  final double fontSize;
  final Color color;

  double _elapsed = 0;

  String get displayText => points > 0 ? '$text$points' : text;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    position.y -= driftSpeed * dt;
    if (_elapsed >= lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1.0 - (_elapsed / lifetime)).clamp(0.0, 1.0);
    final style = TextStyle(
      color: color.withValues(alpha: opacity),
      fontSize: fontSize,
      fontFamily: 'monospace',
    );
    TextPaint(style: style).render(canvas, displayText, Vector2.zero());
  }
}

// ---------------------------------------------------------------------------
// Shared HUD component
// ---------------------------------------------------------------------------

/// Renders score and lives in the top area of the game.
/// Uses a consistent monospace style across all games.
class SharedHudComponent extends PositionComponent {
  SharedHudComponent({
    required this.game,
    this.scorePosition,
    this.livesPosition,
    this.fontSize = 8,
    this.color = Pico8Palette.white,
  }) : super(priority: 50);

  final BaseArcadeGame game;
  final Vector2? scorePosition;
  final Vector2? livesPosition;
  final double fontSize;
  final Color color;

  late final TextPaint _textPaint;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _textPaint = TextPaint(
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontFamily: 'monospace',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final res = BaseArcadeGame.resolution;

    final sPos = scorePosition ?? Vector2(4, 4);
    final lPos = livesPosition ?? Vector2(res.x - 52, 4);

    _textPaint.render(canvas, 'SCORE:${game.score}', sPos);
    _textPaint.render(canvas, 'LIVES:${game.lives}', lPos);
  }
}
