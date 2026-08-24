import 'dart:ui' show Offset;
import 'simple_object_detector.dart';

/// Une position connue à un instant donné (utilisé pour la trajectoire ET
/// pour interpoler la position du Porteur pendant le replay, Étape 8).
class TrackPoint {
  final int timeMs;
  final Offset position;
  const TrackPoint(this.timeMs, this.position);
}

/// Un objet suivi au fil des frames : sa dernière position connue,
/// son historique de positions (= la trajectoire), et depuis combien
/// de frames on ne l'a plus retrouvé.
class Track {
  String id; // mutable : la routine (Étape 5) peut relabelliser un track
  Offset centroid;
  IntRect box;
  int missedFrames = 0;
  bool isCarrier = false; // Étape 4/5 : verrouillage lié à L'OBJET, pas à son label

  /// Moyenne mobile (lissée) de l'aire de la boîte englobante. Sert de
  /// "signature de taille" au Père (Étape 6) pour vérifier après coup que
  /// les ID n'ont pas été mélangés lors d'un croisement.
  double avgArea = 0;

  final List<TrackPoint> history = [];

  Track({required this.id, required this.centroid, required this.box}) {
    avgArea = (box.width * box.height).toDouble();
  }
}

/// Tracker "Centroid Tracking" : une technique classique et très légère
/// (pas de réseau de neurones, pas de flux optique OpenCV) qui associe
/// les détections d'une frame à celles de la frame précédente en se basant
/// simplement sur la distance entre leurs centres.
///
/// Comme les 3 objets sont presque identiques, on ne peut pas les
/// reconnaître par leur apparence : on suppose plutôt qu'un objet ne se
/// déplace pas énormément entre deux frames analysées (échantillonnées
/// toutes les ~500ms), donc "le plus proche voisin" = probablement le
/// même objet. C'est une hypothèse raisonnable pour du Mode Fichier avec
/// un intervalle d'échantillonnage court.
class CentroidTracker {
  final List<Track> tracks = [];

  /// Distance max (en pixels, sur l'image réduite à maxWidth) entre deux
  /// frames pour considérer qu'il s'agit du même objet. À augmenter si tes
  /// objets bougent vite ou si l'intervalle d'échantillonnage est grand.
  final double maxDistance;

  /// Nombre de frames consécutives sans détection toléré avant d'abandonner
  /// un track (gère les occlusions brèves ou un objet mal détecté sur 1-2 frames).
  final int maxMissed;

  static const _labels = ['A', 'B', 'C'];

  CentroidTracker({this.maxDistance = 80, this.maxMissed = 3});

  /// Marque le track qui porte actuellement `id` comme étant le Porteur.
  /// À appeler UNE SEULE FOIS, juste après la toute première frame (celle
  /// utilisée aussi pour la sélection manuelle à l'Étape 4), donc avant
  /// toute permutation de la routine.
  ///
  /// Important (Étape 5) : le verrouillage se fait sur l'OBJET (`isCarrier`
  /// sur le Track lui-même), pas sur la chaîne de caractères "A"/"B"/"C".
  /// Comme la routine peut relabelliser les objets en cours de route
  /// (ex: "A" devient "B" après un échange scripté), s'appuyer sur le label
  /// casserait le verrouillage dès la première permutation.
  void markCarrier(String id) {
    for (final t in tracks) {
      if (t.id == id) {
        t.isCarrier = true;
        return;
      }
    }
  }

  /// Applique une permutation d'ID connue (fournie par la machine à états
  /// de la routine, Étape 5). Calculée en une passe pour éviter qu'une
  /// réaffectation n'en écrase une autre en cours de route.
  void applyIdPermutation(Map<String, String> permutation) {
    final updates = <Track, String>{};
    for (final t in tracks) {
      final newId = permutation[t.id];
      if (newId != null) updates[t] = newId;
    }
    updates.forEach((t, newId) => t.id = newId);
  }

  void update(List<DetectedObject> detections, int timeMs) {
    final centroids = detections
        .map((d) => Offset(
              d.box.left + d.box.width / 2,
              d.box.top + d.box.height / 2,
            ))
        .toList();

    // Premier appel : on crée les 3 tracks, ID attribué gauche -> droite
    // (comme à l'Étape 2), c'est notre seul point de départ possible.
    if (tracks.isEmpty) {
      final order = List<int>.generate(detections.length, (i) => i)
        ..sort((a, b) => centroids[a].dx.compareTo(centroids[b].dx));
      for (int i = 0; i < order.length && i < _labels.length; i++) {
        final idx = order[i];
        final t = Track(id: _labels[i], centroid: centroids[idx], box: detections[idx].box);
        t.history.add(TrackPoint(timeMs, t.centroid));
        tracks.add(t);
      }
      return;
    }

    // Association gloutonne (greedy) : on associe d'abord les paires
    // (track, détection) les plus proches, tant qu'elles ne sont pas déjà
    // utilisées. Simple, léger, et suffisant pour seulement 3 objets.
    final candidates = <(int trackIdx, int detIdx, double dist)>[];
    for (int ti = 0; ti < tracks.length; ti++) {
      for (int di = 0; di < centroids.length; di++) {
        final dist = (tracks[ti].centroid - centroids[di]).distance;
        candidates.add((ti, di, dist));
      }
    }
    candidates.sort((a, b) => a.$3.compareTo(b.$3));

    final usedTracks = <int>{};
    final usedDets = <int>{};
    for (final c in candidates) {
      if (usedTracks.contains(c.$1) || usedDets.contains(c.$2)) continue;
      if (c.$3 > maxDistance) continue; // trop loin : probablement pas le même objet
      final track = tracks[c.$1];
      track.centroid = centroids[c.$2];
      track.box = detections[c.$2].box; // gère le changement de taille : on prend la nouvelle boîte telle quelle
      track.missedFrames = 0;
      track.history.add(TrackPoint(timeMs, track.centroid));
      // Lissage exponentiel de la taille : 80% ancien / 20% nouveau, pour
      // que la "signature de taille" ne réagisse pas au moindre bruit
      // ponctuel mais reflète quand même les vraies évolutions.
      final newArea = (track.box.width * track.box.height).toDouble();
      track.avgArea = track.avgArea * 0.8 + newArea * 0.2;
      usedTracks.add(c.$1);
      usedDets.add(c.$2);
    }

    for (int ti = 0; ti < tracks.length; ti++) {
      if (!usedTracks.contains(ti)) {
        tracks[ti].missedFrames++;
      }
    }
    tracks.removeWhere((t) => !t.isCarrier && t.missedFrames > maxMissed);

    // Détections non associées à un track existant : volontairement ignorées.
    // On connaît le nombre d'objets (3) dès la première frame, donc on
    // n'en crée pas de nouveaux en cours de route : ça éviterait de mélanger
    // les ID A/B/C si un objet est mal détecté une frame puis réapparaît.
  }
}
