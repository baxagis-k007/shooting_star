import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

// Point d'entrée unique de l'application.
// Pas de gestion d'état lourde (pas de Provider/Bloc/Riverpod) pour rester
// aussi léger que possible en RAM : on utilise uniquement le state management
// natif de Flutter (setState) qui est suffisant pour cette étape.
void main() {
  runApp(const ShootingStarApp());
}

class ShootingStarApp extends StatelessWidget {
  const ShootingStarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shooting Star',
      debugShowCheckedModeBanner: false, // Bannière "debug" désactivée = un peu moins d'overlay à dessiner
      theme: ThemeData(
        // Thème sombre "à la main" plutôt que de charger un thème Material 3
        // complet avec Google Fonts, etc. : ça reste léger.
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC857), // Jaune "étoile filante"
          secondary: Color(0xFF6C63FF),
          surface: Color(0xFF1A1A24),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
