import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

/// Abstract base class that all 20 arcade games must extend.
///
/// Provides shared state (score, lives) and a fixed 256x240 virtual
/// resolution with nearest-neighbor scaling for crisp pixel art.
abstract class BaseArcadeGame extends FlameGame with HasCollisionDetection {
  BaseArcadeGame({required this.gameId});

  final String gameId;
  final ValueNotifier<int> scoreNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> livesNotifier = ValueNotifier<int>(3);

  int get score => scoreNotifier.value;
  set score(int v) => scoreNotifier.value = v;

  int get lives => livesNotifier.value;
  set lives(int v) => livesNotifier.value = v;

  /// Virtual resolution matching the NES/PICO-8 aesthetic.
  static final Vector2 resolution = Vector2(256, 240);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set up a fixed-resolution viewport so the game canvas is always
    // 256x240 logical pixels, scaled with nearest-neighbor filtering.
    camera = CameraComponent.withFixedResolution(
      width: resolution.x,
      height: resolution.y,
    );
    camera.viewfinder.anchor = Anchor.topLeft;
  }

  /// Reset all game state for a fresh session.
  void resetGame();

  /// Called when the player has no remaining lives.
  /// Typically triggers `overlays.add('GameOver')`.
  void onGameOver();
}
