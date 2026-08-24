import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import '../vision/simple_object_detector.dart';

// Écran qui affiche le résultat de la détection sur UNE frame de la vidéo
// (celle où l'utilisateur a appuyé sur "Analyser").
// On travaille sur une image statique, pas en flux continu : c'est ce qui
// garde ça léger, conformément au "Mode Fichier".
class DetectionScreen extends StatefulWidget {
  final String videoPath;
  final int timeMs; // position dans la vidéo au moment de l'analyse

  const DetectionScreen({
    super.key,
    required this.videoPath,
    required this.timeMs,
  });

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  bool _loading = true;
  String? _error;
  Uint8List? _annotatedJpeg;
  List<DetectedObject> _objects = [];

  @override
  void initState() {
    super.initState();
    _runDetection();
  }

  Future<void> _runDetection() async {
    try {
      // 1. Extraction d'UNE SEULE frame, déjà réduite à 480px de large.
      // video_thumbnail utilise le décodeur vidéo natif d'Android (léger),
      // pas besoin de charger toute la vidéo en mémoire.
      final Uint8List? frameBytes = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: widget.timeMs,
        maxWidth: 480,
        quality: 75,
      );

      if (frameBytes == null) {
        throw Exception("Impossible d'extraire une image de la vidéo.");
      }

      final img.Image? original = img.decodeJpg(frameBytes);
      if (original == null) {
        throw Exception("Impossible de décoder l'image extraite.");
      }

      // 2. Détection (Dart pur, cf. simple_object_detector.dart)
      const detector = SimpleObjectDetector();
      final objects = detector.detect(original);

      // 3. On dessine les cadres + labels directement sur l'image.
      for (final obj in objects) {
        img.drawRect(
          original,
          x1: obj.box.left,
          y1: obj.box.top,
          x2: obj.box.left + obj.box.width,
          y2: obj.box.top + obj.box.height,
          color: img.ColorRgb8(255, 200, 87),
          thickness: 2,
        );
        img.drawString(
          original,
          obj.id,
          font: img.arial24,
          x: obj.box.left,
          y: (obj.box.top - 26).clamp(0, original.height - 1),
          color: img.ColorRgb8(255, 200, 87),
        );
      }

      final resultBytes = Uint8List.fromList(img.encodeJpg(original, quality: 85));

      if (!mounted) return;
      setState(() {
        _annotatedJpeg = resultBytes;
        _objects = objects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur pendant l'analyse : $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détection des objets')),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analyse en cours...'),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_annotatedJpeg != null)
                            Image.memory(_annotatedJpeg!),
                          const SizedBox(height: 16),
                          Text(
                            _objects.isEmpty
                                ? "Aucun objet détecté. Essaie d'ajuster le seuil (threshold) dans SimpleObjectDetector."
                                : '${_objects.length} objet(s) détecté(s) : '
                                    '${_objects.map((o) => o.id).join(', ')}',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
