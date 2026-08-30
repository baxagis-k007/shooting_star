import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'detection_screen.dart';
import 'tracking_screen.dart';
import 'carrier_selection_screen.dart';

// Écran de lecture vidéo.
// StatefulWidget nécessaire ici car on doit garder le VideoPlayerController
// en vie tant que l'utilisateur regarde la vidéo.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _controller;
  String? _videoPath; // chemin du fichier, nécessaire pour l'étape "Analyser"
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // On ne charge pas de vidéo au démarrage : on attend que l'utilisateur
    // en choisisse une, pour ne rien garder inutilement en mémoire.
  }

  // Ouvre la galerie et charge la vidéo choisie.
  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickVideo(source: ImageSource.gallery);

      if (file == null) {
        // L'utilisateur a annulé.
        setState(() => _isLoading = false);
        return;
      }

      // IMPORTANT pour la RAM : on libère l'ancien contrôleur AVANT
      // d'en créer un nouveau, pour ne jamais avoir deux vidéos en mémoire
      // en même temps.
      await _controller?.dispose();

      final newController = VideoPlayerController.file(File(file.path));
      await newController.initialize();

      // Pas de lecture automatique en boucle infinie ni de préchargement
      // supplémentaire : on reste au strict minimum.
      setState(() {
        _controller = newController;
        _videoPath = file.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Impossible de lire cette vidéo.";
      });
    }
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  // Recule de 10 secondes dans la vidéo.
  void _rewind10s() {
    final controller = _controller;
    if (controller == null) return;
    final newPosition = controller.value.position - const Duration(seconds: 10);
    controller.seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // Lance l'analyse (Étape 2) sur la frame actuellement affichée.
  void _analyzeCurrentFrame() {
    final controller = _controller;
    final path = _videoPath;
    if (controller == null || path == null) return;

    // On met en pause : on analyse une image fixe, pas la vidéo en mouvement.
    controller.pause();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetectionScreen(
          videoPath: path,
          timeMs: controller.value.position.inMilliseconds,
        ),
      ),
    );
  }

  // Lance le suivi (Étape 3) sur l'ensemble de la vidéo.
  void _trackObjects() {
    final controller = _controller;
    final path = _videoPath;
    if (controller == null || path == null) return;

    controller.pause();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          videoPath: path,
          durationMs: controller.value.duration.inMilliseconds,
        ),
      ),
    );
  }

  // Lance la sélection du Porteur (Étape 4), puis le tracking avec surlignage.
  void _identifyCarrier() {
    final controller = _controller;
    final path = _videoPath;
    if (controller == null || path == null) return;

    controller.pause();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarrierSelectionScreen(
          videoPath: path,
          durationMs: controller.value.duration.inMilliseconds,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Libération OBLIGATOIRE du contrôleur vidéo : sans ça, la mémoire
    // native (buffers vidéo) n'est jamais rendue au système.
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyser une vidéo')),
      body: SafeArea(
        child: Center(
          child: _buildBody(),
        ),
      ),
      // Bouton pour choisir/changer de vidéo, toujours accessible.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _pickVideo,
        icon: const Icon(Icons.video_library_outlined),
        label: Text(_controller == null ? 'Choisir une vidéo' : 'Changer'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }

    if (_errorMessage != null) {
      return Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent));
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Text(
        'Aucune vidéo sélectionnée.\nAppuyez sur "Choisir une vidéo".',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade400),
      );
    }

    // Lecteur vidéo simple : aspect ratio natif + contrôles minimalistes.
    // AnimatedBuilder écoute le controller (déjà un ChangeNotifier) pour que
    // l'icône Lecture/Pause se mette à jour automatiquement (ex: fin de vidéo)
    // SANS ajouter de package supplémentaire ni de setState global coûteux.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            const SizedBox(height: 8),

            // Barre de progression : widget natif fourni par video_player,
            // très léger (pas de package tiers type chewie).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true, // permet de tirer la barre pour avancer/reculer
                colors: VideoProgressColors(
                  playedColor: Theme.of(context).colorScheme.primary,
                  bufferedColor: Colors.grey.shade700,
                  backgroundColor: Colors.grey.shade900,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Boutons de contrôle.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 32,
                  icon: const Icon(Icons.replay_10),
                  tooltip: 'Reculer de 10s',
                  onPressed: _rewind10s,
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 48,
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _togglePlayPause,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Étape 2 : lance la détection des 3 objets sur la frame actuelle.
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Analyser (détecter les 3 objets)'),
              onPressed: _analyzeCurrentFrame,
            ),
            const SizedBox(height: 8),

            // Étape 3 : suit les 3 objets sur toute la vidéo.
            OutlinedButton.icon(
              icon: const Icon(Icons.timeline),
              label: const Text('Suivi (tracking A/B/C)'),
              onPressed: _trackObjects,
            ),
            const SizedBox(height: 8),

            // Étape 4 : sélection manuelle du Porteur + surlignage permanent.
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.touch_app),
              label: const Text('Identifier le Porteur'),
              onPressed: _identifyCarrier,
            ),
          ],
        );
      },
    );
  }
}
