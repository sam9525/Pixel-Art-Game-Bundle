import 'dart:ui' show Color;

import 'base_game.dart';
import 'palette.dart';
import '../games/pong.dart';
import '../games/snake.dart';
import '../games/breakout.dart';
import '../games/flappy.dart';
import '../games/space_invaders.dart';

/// Metadata and factory for a single arcade game.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.factory,
    required this.color,
    required this.icon,
  });

  final String id;
  final String title;
  final BaseArcadeGame Function() factory;

  /// Accent color for the game card's top border.
  final Color color;

  /// Display icon/emoji shown on the game card.
  final String icon;
}

/// Central registry of all available games.
///
/// [GameWrapperScreen] looks up entries here to instantiate a fresh
/// game instance per session.
final Map<String, GameEntry> gameRegistry = {
  'pong': GameEntry(
    id: 'pong',
    title: 'Pong',
    factory: () => PongGame(),
    color: Pico8Palette.blue,
    icon: '🏓',
  ),
  'snake': GameEntry(
    id: 'snake',
    title: 'Snake',
    factory: () => SnakeGame(),
    color: Pico8Palette.green,
    icon: '🐍',
  ),
  'breakout': GameEntry(
    id: 'breakout',
    title: 'Breakout',
    factory: () => BreakoutGame(),
    color: Pico8Palette.orange,
    icon: '🧱',
  ),
  'flappy': GameEntry(
    id: 'flappy',
    title: 'Flappy Bird',
    factory: () => FlappyGame(),
    color: Pico8Palette.yellow,
    icon: '🐦',
  ),
  'space_invaders': GameEntry(
    id: 'space_invaders',
    title: 'Space Invaders',
    factory: () => SpaceInvadersGame(),
    color: Pico8Palette.lavender,
    icon: '👾',
  ),
};
