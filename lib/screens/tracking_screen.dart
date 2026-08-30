import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import '../vision/simple_object_detector.dart';
import '../vision/object_tracker.dart';
import '../vision/routine_state_machine.dart';
import '../vision/parent_supervisor.dart';
import '../vision/confidence_timeline.dart';
import 'final_verification_screen.dart';
import 'replay_screen.dart';

// Écran de tracking (Étape 3).
// Principe "Mode Fichier" : on échantillonne la vidéo à intervalle régulier
// (par défaut toutes les 500ms), on détecte les objets sur chaque frame
// échantillonnée, et on les associe d'une frame à l'autre avec un tracker
// centroid-based léger (voir object_tracker.dart).
//
// IMPORTANT pour la RAM : une seule frame décodée en mémoire à la fois.
// On ne garde JAMAIS toutes les frames : seulement leurs positions (Offset),
// et la dernière frame décodée pour l'affichage final avec les trajectoires.
class TrackingScreen extends StatefulWidget {
  final String videoPath;
  final int durationMs;
  // Étape 4 : si renseigné, cet ID (A, B ou C) reçoit un surlignage fort
  // et permanent ; les autres objets restent discrets.
  final String? carrierId;

  const TrackingScreen({
    super.key,
    required this.videoPath,
    required this.durationMs,
    this.carrierId,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  bool _loading = true;
  String? _error;
  Uint8List? _resultJpeg;
  int _resultWidth = 0;
  int _resultHeight = 0;
  int _framesProcessed = 0;
  int _framesTotal = 0;
  final CentroidTracker _tracker = CentroidTracker();
  late final RoutineStateMachine _routine = RoutineStateMachine(defaultRoutine);
  final ParentSupervisor _father = ParentSupervisor(); // Étape 6
  RoutineStep? _currentStep;
  bool _carrierMarked = false;
  final List<ConfidenceSample> _confidence = []; // Étape 8

  // Intervalle entre deux frames analysées.
  // Plus PETIT = trajectoire plus précise mais plus de calcul (plus lent).
  // Plus GRAND = plus léger mais risque de "sauter" un objet qui bouge vite.
  // 500ms est un bon point de départ pour un CPU d'entrée de gamme.
  static const int _sampleIntervalMs = 500;

  @override
  void initState() {
    super.initState();
    // Le verrouillage du Porteur (isCarrier) est appliqué juste après la
    // toute première frame analysée, une fois les tracks créés -- voir la
    // boucle dans _runTracking().
    _runTracking();
  }

  Future<void> _runTracking() async {
    try {
      final timestamps = <int>[
        for (int t = 0; t < widget.durationMs; t += _sampleIntervalMs) t,
      ];
      if (timestamps.isEmpty || timestamps.last != widget.durationMs) {
        timestamps.add(widget.durationMs);
      }
      setState(() => _framesTotal = timestamps.length);

      const detector = SimpleObjectDetector();
      img.Image? lastFrame;

      // Boucle SÉQUENTIELLE (pas de traitement parallèle) : volontaire pour
      // ne jamais avoir plusieurs frames décodées en mémoire simultanément.
      for (final t in timestamps) {
        final bytes = await VideoThumbnail.thumbnailData(
          video: widget.videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: t,
          maxWidth: 480,
          quality: 70,
        );
        if (bytes == null) continue;

        final frame = img.decodeJpg(bytes);
        if (frame == null) continue;

        final detections = detector.detect(frame);
        _tracker.update(detections, t);

        // Étape 4 : verrouille le Porteur sur l'OBJET (pas le label), une
        // seule fois, juste après la création des tracks sur la 1ère frame.
        if (!_carrierMarked && widget.carrierId != null && _tracker.tracks.isNotEmpty) {
          _tracker.markCarrier(widget.carrierId!);
          _carrierMarked = true;
        }

        // Étape 5 : applique la permutation d'ID connue si on vient de
        // franchir le début d'une étape d'échange/rotation scriptée.
        // Étape 6 : le Père ("Système 2") vérifie juste après, avec la
        // taille des objets -- appel bon marché, aucune image décodée.
        final logCountBefore = _father.log.length;
        _routine.applyScheduledPermutations(t, widget.durationMs, (perm) {
          _tracker.applyIdPermutation(perm);
          _father.verifyAndCorrect(_tracker, t, reason: 'routine');
        });
        _currentStep = _routine.currentStep(t, widget.durationMs);

        // Croisement "sauvage" (non prévu par la routine) : deux tracks
        // anormalement proches -> on fait aussi vérifier le Père ici.
        // C'est ÇA "seulement aux moments critiques" : le reste du temps,
        // le Père ne fait strictement rien.
        if (_minPairwiseDistance(_tracker.tracks) < _father.crossingDistance) {
          _father.verifyAndCorrect(_tracker, t, reason: 'croisement');
        }

        // Étape 8 : timeline de confiance -- calculée gratuitement à partir
        // de ce qu'on sait déjà (le Père a-t-il dû corriger ? le Porteur
        // a-t-il été retrouvé cette frame ?), aucun calcul supplémentaire.
        final carrierTrack = _tracker.tracks.cast<Track?>().firstWhere(
              (tr) => tr!.isCarrier,
              orElse: () => null,
            );
        final ConfidenceLevel level;
        if (_father.log.length > logCountBefore) {
          level = ConfidenceLevel.corrected;
        } else if (carrierTrack == null || carrierTrack.missedFrames > 0) {
          level = ConfidenceLevel.missing;
        } else {
          level = ConfidenceLevel.ok;
        }
        _confidence.add(ConfidenceSample(t, level));

        lastFrame = frame; // remplace la précédente : une seule en mémoire
        if (mounted) setState(() => _framesProcessed++);
      }

      if (lastFrame == null) {
        throw Exception("Aucune frame n'a pu être analysée.");
      }

      // Vérification finale du Père (Étape 6 : "et à la fin").
      _father.verifyAndCorrect(_tracker, timestamps.last, reason: 'fin de vidéo');

      // Dessin final : trajectoire + dernière position de chaque objet.
      // Le Porteur (Étape 4) est mis en évidence fortement ; les autres
      // objets restent discrets pour ne pas attirer l'œil.
      for (final track in _tracker.tracks) {
        final bool isCarrier = track.isCarrier;

        // Trajectoire : bien visible pour le Porteur, très discrète sinon.
        for (int i = 1; i < track.history.length; i++) {
          final p1 = track.history[i - 1].position;
          final p2 = track.history[i].position;
          img.drawLine(
            lastFrame,
            x1: p1.dx.toInt(),
            y1: p1.dy.toInt(),
            x2: p2.dx.toInt(),
            y2: p2.dy.toInt(),
            color: isCarrier
                ? img.ColorRgb8(255, 200, 87)
                : img.ColorRgb8(90, 90, 100),
            thickness: isCarrier ? 3 : 1,
          );
        }

        if (isCarrier) {
          _drawCarrierHighlight(lastFrame, track.box);
        } else {
          // Style discret : cadre fin, gris, juste la lettre.
          img.drawRect(
            lastFrame,
            x1: track.box.left,
            y1: track.box.top,
            x2: track.box.left + track.box.width,
            y2: track.box.top + track.box.height,
            color: img.ColorRgb8(150, 150, 160),
            thickness: 1,
          );
          img.drawString(
            lastFrame,
            track.id,
            font: img.arial14,
            x: track.box.left,
            y: (track.box.top - 16).clamp(0, lastFrame.height - 1),
            color: img.ColorRgb8(150, 150, 160),
          );
        }
      }

      final resultBytes = Uint8List.fromList(img.encodeJpg(lastFrame, quality: 85));

      if (!mounted) return;
      setState(() {
        _resultJpeg = resultBytes;
        _resultWidth = lastFrame!.width;
        _resultHeight = lastFrame.height;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur pendant le suivi : $e";
        _loading = false;
      });
    }
  }

  // Surlignage fort et permanent du Porteur : halo jaune (cercles concentriques
  // semi-transparents) + cadre épais + texte "PORTEUR". Simple à calculer,
  // aucune dépendance supplémentaire.
  void _drawCarrierHighlight(img.Image frame, IntRect box) {
    final cx = box.left + box.width ~/ 2;
    final cy = box.top + box.height ~/ 2;
    final baseRadius = (box.width > box.height ? box.width : box.height) ~/ 2;

    // Halo : quelques cercles semi-transparents (alpha décroissant vers l'extérieur).
    for (int i = 0; i < 4; i++) {
      img.drawCircle(
        frame,
        x: cx,
        y: cy,
        radius: baseRadius + 6 + i * 5,
        color: img.ColorRgba8(255, 200, 87, 70 - i * 15),
      );
    }

    // Cadre épais.
    img.drawRect(
      frame,
      x1: box.left - 4,
      y1: box.top - 4,
      x2: box.left + box.width + 4,
      y2: box.top + box.height + 4,
      color: img.ColorRgb8(255, 200, 87),
      thickness: 4,
    );

    // Étiquette bien visible.
    img.drawString(
      frame,
      'PORTEUR',
      font: img.arial24,
      x: box.left,
      y: (box.top - 30).clamp(0, frame.height - 1),
      color: img.ColorRgb8(255, 200, 87),
    );
  }

  // Distance minimale entre deux tracks quelconques (0 s'il y en a moins de 2).
  // Coût quasi nul : juste de la géométrie sur des points déjà en mémoire.
  double _minPairwiseDistance(List<Track> tracks) {
    if (tracks.length < 2) return double.infinity;
    double minDist = double.infinity;
    for (int i = 0; i < tracks.length; i++) {
      for (int j = i + 1; j < tracks.length; j++) {
        final d = (tracks[i].centroid - tracks[j].centroid).distance;
        if (d < minDist) minDist = d;
      }
    }
    return minDist;
  }

  // Étape 8 : petit point de légende pour la timeline de confiance.
  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ],
    );
  }

  Track? _carrierTrackOrNull() {
    for (final t in _tracker.tracks) {
      if (t.isCarrier) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des objets')),
      body: SafeArea(
        child: Center(
          child: _loading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Analyse : $_framesProcessed / $_framesTotal frames'),
                    if (_currentStep != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Étape ${_currentStep!.index}/10 — ${_currentStep!.label}',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ),
                  ],
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --- Image annotée + timeline de confiance juste dessous ---
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _resultJpeg != null ? Image.memory(_resultJpeg!) : const SizedBox(),
                          ),
                          const SizedBox(height: 6),
                          ConfidenceTimelineBar(samples: _confidence),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _legendDot(Colors.greenAccent, 'OK'),
                              const SizedBox(width: 12),
                              _legendDot(Colors.orangeAccent, 'Corrigé'),
                              const SizedBox(width: 12),
                              _legendDot(Colors.redAccent, 'Perdu'),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // --- Résumé, dans un encart pour bien le séparer de l'image ---
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_currentStep != null)
                                  Text(
                                    'Étape finale atteinte : ${_currentStep!.index}/10 — ${_currentStep!.label}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_tracker.tracks.length} objet(s) suivi(s) : '
                                  '${_tracker.tracks.map((t) => t.id).join(', ')}',
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _father.log.isEmpty
                                      ? 'Aucune correction du Père nécessaire.'
                                      : '${_father.log.length} correction(s) du Père :',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                for (final c in _father.log)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      c.description,
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- Actions ---
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Vérifier le résultat'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FinalVerificationScreen(
                                    frameJpeg: _resultJpeg!,
                                    frameWidth: _resultWidth,
                                    frameHeight: _resultHeight,
                                    tracks: _tracker.tracks,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (_carrierTrackOrNull() != null) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.slow_motion_video),
                              label: const Text('Revoir en ralenti (Porteur)'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReplayScreen(
                                      videoPath: widget.videoPath,
                                      carrierHistory: _carrierTrackOrNull()!.history,
                                      analysisWidth: _resultWidth,
                                      analysisHeight: _resultHeight,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
