import 'package:flutter/material.dart';

// Écran Options : volontairement minimal pour l'instant.
// StatelessWidget car aucun état interne à gérer à ce stade.
class OptionsScreen extends StatelessWidget {
  const OptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // L'AppBar fournit déjà une flèche retour automatique,
      // mais on ajoute aussi un bouton explicite dans le corps
      // comme demandé.
      appBar: AppBar(title: const Text('Options & Paramètres')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Options & Paramètres',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun réglage disponible pour le moment.\n'
                'Cet écran sera complété dans une prochaine étape.',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const Spacer(),
              // Bouton retour explicite, centré en bas.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour'),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
