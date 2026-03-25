import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/palette.dart';
import 'shared/arcade_hub.dart';
import 'shared/game_wrapper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const PixelArcadeApp());
}

class PixelArcadeApp extends StatelessWidget {
  const PixelArcadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Arcade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Pico8Palette.black,
        fontFamily: 'PressStart2P',
        colorScheme: ColorScheme.dark(
          surface: Pico8Palette.black,
          primary: Pico8Palette.blue,
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (_) => const ArcadeHubScreen(),
          );
        }
        if (settings.name != null && settings.name!.startsWith('/game/')) {
          final gameId = settings.name!.replaceFirst('/game/', '');
          return MaterialPageRoute(
            builder: (_) => GameWrapperScreen(gameId: gameId),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const ArcadeHubScreen(),
        );
      },
    );
  }
}
