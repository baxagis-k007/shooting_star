import 'package:flutter/material.dart';

/// Niveau de confiance à un instant donné, calculé sans aucun calcul
/// supplémentaire : juste une lecture de l'état déjà connu du tracker et
/// du journal du Père (Étape 6) à ce moment précis.
enum ConfidenceLevel { ok, corrected, missing }

class ConfidenceSample {
  final int timeMs;
  final ConfidenceLevel level;
  const ConfidenceSample(this.timeMs, this.level);
}

/// Barre horizontale simple : un segment par frame échantillonnée, coloré
/// selon le niveau de confiance. Pas de bibliothèque de graphiques (trop
/// lourd) -- juste une Row de Container colorés.
class ConfidenceTimelineBar extends StatelessWidget {
  final List<ConfidenceSample> samples;

  const ConfidenceTimelineBar({super.key, required this.samples});

  Color _colorFor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.ok:
        return Colors.greenAccent;
      case ConfidenceLevel.corrected:
        return Colors.orangeAccent;
      case ConfidenceLevel.missing:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            for (final s in samples)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.3),
                  color: _colorFor(s.level),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
