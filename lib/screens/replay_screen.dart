import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../vision/object_tracker.dart';

// Étape 8 : replay en ralenti.
//
// IMPORTANT pour la RAM/CPU : on NE régénère PAS une nouvelle vidéo
// annotée (ça demanderait un encodeur vidéo, bien trop lourd pour ce
// téléphone). On se contente de rejouer la vidéo ORIGINALE via
// video_player (déjà utilisé à l'Étape 1) à vitesse réduite, et on
// superpose un halo dont la position est INTERPOLÉE à partir des points
// déjà calculés pendant le tracking -- aucun nouveau calcul de vision.
class ReplayScreen extends StatefulWidget {
  final String videoPath;
  final List<TrackPoint> carrierHistory;
  final int analysisWidth; // résolution utilisée pendant l'analyse (480 par défaut)
  final int analysisHeight;

  const ReplayScreen({
    super.key,
    required this.videoPath,
    required this.carrierHistory,
    required this.analysisWidth,
    required this.analysisHeight,
  });

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(File(widget.videoPath));
    await controller.initialize();
    await controller.setPlaybackSpeed(0.5); // ralenti natif, aucun coût CPU/RAM supplémentaire
    await controller.play();
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  // Interpolation linéaire entre les deux points de trajectoire encadrant
  // l'instant courant. Coût négligeable (une petite liste, un parcours).
  Offset? _interpolatedPosition(int currentMs) {
    final h = widget.carrierHistory;
    if (h.isEmpty) return null;
    if (currentMs <= h.first.timeMs) return h.first.position;
    if (currentMs >= h.last.timeMs) return h.last.position;

    for (int i = 1; i < h.length; i++) {
      if (currentMs <= h[i].timeMs) {
        final p0 = h[i - 1];
        final p1 = h[i];
        final span = (p1.timeMs - p0.timeMs).clamp(1, 1 << 30);
        final f = (currentMs - p0.timeMs) / span;
        return Offset(
          p0.position.dx + (p1.position.dx - p0.position.dx) * f,
          p0.position.dy + (p1.position.dy - p0.position.dy) * f,
        );
      }
    }
    return h.last.position;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Replay ralenti — Porteur')),
      body: SafeArea(
        child: Center(
          child: controller == null || !controller.value.isInitialized
              ? const CircularProgressIndicator()
              : AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaleX = constraints.maxWidth / widget.analysisWidth;
                      final scaleY = constraints.maxHeight / widget.analysisHeight;

                      return AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          final pos = _interpolatedPosition(
                            controller.value.position.inMilliseconds,
                          );
                          return Stack(
                            children: [
                              VideoPlayer(controller),
                              if (pos != null)
                                Positioned(
                                  left: pos.dx * scaleX - 30,
                                  top: pos.dy * scaleY - 30,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFFFC857),
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFC857).withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              },
              child: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }
}
