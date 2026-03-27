import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/base_game.dart';
import '../core/palette.dart';
import '../core/registry.dart';
import 'game_over_overlay.dart';
import 'pause_overlay.dart';
import 'pixel_hud.dart';
import 'start_overlay.dart';

/// Wraps a [BaseArcadeGame] in a [GameWidget] with HUD, pause, and
/// game-over overlays.
///
/// Expects a `gameId` string passed via [ModalRoute] arguments that
/// matches a key in [gameRegistry].
class GameWrapperScreen extends StatefulWidget {
  const GameWrapperScreen({super.key, required this.gameId});

  final String gameId;

  @override
  State<GameWrapperScreen> createState() => _GameWrapperScreenState();
}

class _GameWrapperScreenState extends State<GameWrapperScreen> {
  late String _gameId;
  late BaseArcadeGame _game;
  int _highScore = 0;

  @override
  void initState() {
    super.initState();
    _gameId = widget.gameId;
    _game = _createGame();
    _loadHighScore();
  }

  BaseArcadeGame _createGame() {
    final entry = gameRegistry[_gameId];
    if (entry == null) {
      throw ArgumentError('No game registered with id "$_gameId"');
    }
    final game = entry.factory();
    // Pause the game until the player presses start.
    game.paused = true;
    return game;
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('highscore_$_gameId') ?? 0;
    if (mounted) {
      setState(() => _highScore = stored);
    }
  }

  Future<void> _saveHighScore(int score) async {
    if (score > _highScore) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('highscore_$_gameId', score);
      if (mounted) {
        setState(() => _highScore = score);
      }
    }
  }

  void _onStart() {
    _game.overlays.remove('Start');
    _game.paused = false;
  }

  void _onPause() {
    _game.overlays.add('Pause');
    _game.paused = true;
  }

  void _onResume() {
    _game.overlays.remove('Pause');
    _game.paused = false;
  }

  void _onRestart() {
    setState(() {
      _game = _createGame();
    });
    // Add Start overlay after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _game.overlays.add('Start');
    });
  }

  void _onQuit() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pico8Palette.black,
      body: GameWidget(
        key: ValueKey(_game),
        game: _game,
        initialActiveOverlays: const ['Hud', 'Start'],
        overlayBuilderMap: {
          'Start': (BuildContext ctx, Game game) {
            final entry = gameRegistry[_gameId]!;
            return StartOverlay(
              title: entry.title,
              icon: entry.icon,
              highScore: _highScore,
              accentColor: entry.color,
              onStart: _onStart,
              onQuit: _onQuit,
            );
          },
          'Hud': (BuildContext ctx, Game game) {
            final arcadeGame = game as BaseArcadeGame;
            return ListenableBuilder(
              listenable: Listenable.merge([
                arcadeGame.scoreNotifier,
                arcadeGame.livesNotifier,
              ]),
              builder: (context, _) => PixelHud(
                score: arcadeGame.score,
                lives: arcadeGame.lives,
                onPause: _onPause,
              ),
            );
          },
          'GameOver': (BuildContext ctx, Game game) {
            final arcadeGame = game as BaseArcadeGame;
            final entry = gameRegistry[_gameId]!;
            _saveHighScore(arcadeGame.score);
            return GameOverOverlay(
              title: entry.title,
              icon: entry.icon,
              accentColor: entry.color,
              score: arcadeGame.score,
              highScore: _highScore,
              onRestart: _onRestart,
              onQuit: _onQuit,
            );
          },
          'Pause': (BuildContext ctx, Game game) {
            final entry = gameRegistry[_gameId]!;
            return PauseOverlay(
              title: entry.title,
              icon: entry.icon,
              accentColor: entry.color,
              onResume: _onResume,
              onQuit: _onQuit,
            );
          },
        },
      ),
    );
  }
}
