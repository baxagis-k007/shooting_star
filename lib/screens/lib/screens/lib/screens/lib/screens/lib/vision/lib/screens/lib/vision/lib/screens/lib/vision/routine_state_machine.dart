/// Étape 5 : la routine est SCRIPTÉE et connue à l'avance (ce n'est pas une
/// improvisation) -- c'est une information précieuse qu'on peut exploiter
/// directement, plutôt que d'essayer de "deviner" par vision (rotation,
/// échange...) ce que le tracker de l'Étape 3 ne peut de toute façon pas
/// détecter de manière fiable avec des objets quasi identiques.
///
/// Principe : chaque étape démarre à un instant connu (exprimé en fraction
/// 0.0-1.0 de la durée totale de la vidéo). Si une étape correspond à un
/// échange de places connu (swap OU rotation à 3, c'est la même mécanique),
/// on fournit la permutation exacte des ID -- elle est appliquée au bon
/// moment SANS dépendre de la détection visuelle du croisement, qui est
/// justement le moment où le tracking par proximité est le moins fiable.
library;

enum StepType { pause, swap, rotation, roundTrip }

class RoutineStep {
  final int index; // 1 à 10
  final String label;
  final StepType type;

  /// Fraction (0.0-1.0) de la durée totale de la vidéo à laquelle cette
  /// étape DÉBUTE. Exemple : si l'étape démarre à 12s sur une vidéo de 60s,
  /// startFraction = 0.20.
  final double startFraction;

  /// Si cette étape correspond à un échange/rotation connu, la permutation
  /// à appliquer aux ID à ce moment précis.
  /// Clé = ID actuel, valeur = nouvel ID. Exemple : {'A':'B','B':'A'} veut
  /// dire "l'objet qui s'appelait A s'appelle maintenant B et vice-versa".
  /// Laisser à null si l'étape ne change pas l'affectation des ID (pause,
  /// aller-retour, etc.).
  final Map<String, String>? idPermutation;

  const RoutineStep({
    required this.index,
    required this.label,
    required this.type,
    required this.startFraction,
    this.idPermutation,
  });
}

/// ⚠️ EXEMPLE À PERSONNALISER ⚠️
/// Ceci est un squelette avec 10 étapes de durée égale et des permutations
/// arbitraires, juste pour que le code compile et tourne. Remplace les
/// `startFraction` par les instants réels de TA routine (regarde ta vidéo,
/// note les secondes de début de chaque étape, divise par la durée totale),
/// et les `idPermutation` par les échanges réels qui se produisent.
const List<RoutineStep> defaultRoutine = [
  RoutineStep(index: 1, label: 'Position de départ', type: StepType.pause, startFraction: 0.00),
  RoutineStep(index: 2, label: 'Échange A-B', type: StepType.swap, startFraction: 0.10,
      idPermutation: {'A': 'B', 'B': 'A'}),
  RoutineStep(index: 3, label: 'Pause', type: StepType.pause, startFraction: 0.20),
  RoutineStep(index: 4, label: 'Aller-retour B', type: StepType.roundTrip, startFraction: 0.30),
  RoutineStep(index: 5, label: 'Rotation A-B-C', type: StepType.rotation, startFraction: 0.40,
      idPermutation: {'A': 'B', 'B': 'C', 'C': 'A'}),
  RoutineStep(index: 6, label: 'Pause', type: StepType.pause, startFraction: 0.50),
  RoutineStep(index: 7, label: 'Échange A-C', type: StepType.swap, startFraction: 0.60,
      idPermutation: {'A': 'C', 'C': 'A'}),
  RoutineStep(index: 8, label: 'Aller-retour C', type: StepType.roundTrip, startFraction: 0.70),
  RoutineStep(index: 9, label: 'Rotation finale', type: StepType.rotation, startFraction: 0.85,
      idPermutation: {'A': 'C', 'C': 'B', 'B': 'A'}),
  RoutineStep(index: 10, label: 'Position finale', type: StepType.pause, startFraction: 0.95),
];

class RoutineStateMachine {
  final List<RoutineStep> steps; // doit être trié par startFraction croissant
  int _appliedUntilIndex = 0;

  RoutineStateMachine(this.steps);

  /// Étape correspondant au temps courant, purement basée sur le temps
  /// écoulé (fiable puisque la routine est scriptée à des instants connus).
  RoutineStep currentStep(int elapsedMs, int totalMs) {
    final fraction = totalMs == 0 ? 0.0 : elapsedMs / totalMs;
    RoutineStep current = steps.first;
    for (final s in steps) {
      if (fraction >= s.startFraction) {
        current = s;
      } else {
        break;
      }
    }
    return current;
  }

  /// À appeler à chaque frame analysée pendant le tracking (dans l'ordre
  /// chronologique). Applique automatiquement la permutation d'ID connue
  /// dès qu'on franchit l'instant de départ d'une étape d'échange -- c'est
  /// ÇA qui stabilise le tracking : pas besoin que la détection visuelle
  /// devine juste pendant un croisement rapide, la routine le sait déjà.
  void applyScheduledPermutations(int elapsedMs, int totalMs, void Function(Map<String, String>) applyPermutation) {
    final fraction = totalMs == 0 ? 0.0 : elapsedMs / totalMs;
    for (int i = _appliedUntilIndex; i < steps.length; i++) {
      final step = steps[i];
      if (fraction < step.startFraction) break;
      if (step.idPermutation != null) {
        applyPermutation(step.idPermutation!);
      }
      _appliedUntilIndex = i + 1;
    }
  }
}
