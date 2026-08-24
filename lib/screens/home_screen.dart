import 'package:flutter/material.dart';
import 'video_screen.dart';
import 'options_screen.dart';

// Écran d'accueil : aucun StatefulWidget nécessaire ici, donc on garde
// un simple StatelessWidget (moins d'objets en mémoire, pas de rebuild inutile).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Petit bouton/icône pour aller aux Options, en haut à droite.
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Options',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OptionsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Logo : icône étoile + nom de l'app ---
              const Icon(
                Icons.auto_awesome, // icône "étoile filante" native Material, pas d'image à charger
                size: 64,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(height: 12),
              const Text(
                'Shooting Star',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Analyse de vidéos',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 64),

              // --- Gros bouton principal ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text(
                    'Analyser une vidéo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VideoScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
