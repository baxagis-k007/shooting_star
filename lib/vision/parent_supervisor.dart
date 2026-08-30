import 'object_tracker.dart';

/// Une correction effectuée par le Père, avec le moment et la raison --
/// demandé explicitement : "enregistrer les moments où une correction a
/// été faite".
class Correction {
  final int timeMs;
  final String reason; // 'routine', 'croisement', 'fin de vidéo'
  final String description;

  const Correction({required this.timeMs, required this.reason, required this.description});
}

/// Système 2 ("Père") : contrairement au tracking principal (l'Enfant, dans
/// CentroidTracker, qui tourne à CHAQUE frame échantillonnée), le Père ne
/// s'exécute que ponctuellement, aux moments où une erreur est plausible :
///
///  1. Juste après une permutation scriptée de la routine (Étape 5) -- on
///     vérifie que le résultat est cohérent avec la taille des objets.
///  2. Quand deux tracks se retrouvent anormalement proches (un croisement
///     "sauvage", pas prévu par la routine).
///  3. À la toute fin de la vidéo, en vérification finale.
///
/// Le calcul est volontairement TRÈS léger : pas de nouvelle image
/// décodée, pas de nouvelle détection -- seulement de l'arithmétique sur
/// les données déjà en mémoire (box, avgArea). C'est ce qui garantit qu'il
/// ne pèse pas sur la RAM même appelé plusieurs fois.
class ParentSupervisor {
  final List<Correction> log = [];

  /// En dessous de quelle distance (px, résolution d'analyse 480px) deux
  /// tracks sont considérés "en croisement".
  final double crossingDistance;

  /// Un échange n'est appliqué que si la permutation implicite (déduite de
  /// la taille) réduit l'écart de taille d'au moins ce facteur -- évite de
  /// corriger sur un simple bruit de mesure.
  final double improvementThreshold;

  ParentSupervisor({this.crossingDistance = 40, this.improvementThreshold = 0.6});

  /// Vérifie les paires de tracks et corrige si la taille suggère qu'ils
  /// ont été mélangés. Ne fait rien la plupart du temps (appels bon marché).
  void verifyAndCorrect(CentroidTracker tracker, int timeMs, {required String reason}) {
    final tracks = tracker.tracks;
    if (tracks.length < 2) return;

    for (int i = 0; i < tracks.length; i++) {
      for (int j = i + 1; j < tracks.length; j++) {
        final a = tracks[i];
        final b = tracks[j];

        final areaA = (a.box.width * a.box.height).toDouble();
        final areaB = (b.box.width * b.box.height).toDouble();

        // Coût actuel vs coût si les ID de a et b étaient échangés,
        // par rapport à leur signature de taille habituelle (avgArea).
        final costAsIs = (areaA - a.avgArea).abs() + (areaB - b.avgArea).abs();
        final costSwapped = (areaA - b.avgArea).abs() + (areaB - a.avgArea).abs();

        if (costSwapped < costAsIs * improvementThreshold) {
          // La taille suggère fortement que a et b ont été mélangés :
          // on rétablit en échangeant leur ID, leur statut Porteur, et
          // leur signature de taille (qui "appartient" à l'identité, pas
          // à la position dans la liste).
          final tmpId = a.id;
          a.id = b.id;
          b.id = tmpId;

          final tmpCarrier = a.isCarrier;
          a.isCarrier = b.isCarrier;
          b.isCarrier = tmpCarrier;

          final tmpAvg = a.avgArea;
          a.avgArea = b.avgArea;
          b.avgArea = tmpAvg;

          log.add(Correction(
            timeMs: timeMs,
            reason: reason,
            description:
                '${a.id} ↔ ${b.id} rétablis via la taille (${(timeMs / 1000).toStringAsFixed(1)}s, $reason)',
          ));
        }
      }
    }
  }
}
