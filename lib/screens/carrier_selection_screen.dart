import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import '../vision/simple_object_detector.dart';
import 'tracking_screen.dart';

// Étape 4 : avant de lancer le tracking complet, l'utilisateur touche
// l'objet (A, B ou C) qui contient l'élément caché. Cet objet devient
// le "Porteur" et sera surligné en permanence pendant le suivi.
//
// On travaille sur la toute première frame (t=0), déjà détectée avec le
// détecteur de l'Étape 2 -- aucun calcul supplémentaire lourd ici.
class CarrierSelectionScreen extends StatefulWidget {
  final String videoPath;
  final int durationMs;

  const CarrierSelectionScreen({
    super.key,
    required this.videoPath,
    required this.durationMs,
  });

  @override
  State<CarrierSelectionScreen> createState() => _CarrierSelectionScreenState();
}

class _CarrierSelectionScreenState extends State<CarrierSelectionScreen> {
  bool _loading = true;
  String? _error;
  Uint8List? _frameJpeg;
  int _frameWidth = 0;
  int _frameHeight = 0;
  List<DetectedObject> _objects = [];

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  Future<void> _loadFirstFrame() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        maxWidth: 480,
        quality: 75,
      );
      if (bytes == null) throw Exception("Impossible d'extraire la première frame.");

      final frame = img.decodeJpg(bytes);
      if (frame == null) throw Exception("Impossible de décoder l'image.");

      const detector = SimpleObjectDetector();
      final objects = detector.detect(frame);

      // Cadres fins juste pour repérer visuellement A/B/C avant sélection.
      for (final o in objects) {
        img.drawRect(
          frame,
          x1: o.box.left,
          y1: o.box.top,
          x2: o.box.left + o.box.width,
          y2: o.box.top + o.box.height,
          color: img.ColorRgb8(255, 255, 255),
          thickness: 2,
        );
        img.drawString(
          frame,
          o.id,
          font: img.arial24,
          x: o.box.left,
          y: (o.box.top - 26).clamp(0, frame.height - 1),
          color: img.ColorRgb8(255, 255, 255),
        );
      }

      final jpeg = Uint8List.fromList(img.encodeJpg(frame, quality: 85));

      if (!mounted) return;
      setState(() {
        _frameJpeg = jpeg;
        _frameWidth = frame.width;
        _frameHeight = frame.height;
        _objects = objects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur : $e";
        _loading = false;
      });
    }
  }

  void _selectCarrier(String id) {
    // On remplace cet écran par le tracking direct : pas besoin de revenir
    // en arrière vers la sélection une fois le choix fait.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          videoPath: widget.videoPath,
          durationMs: widget.durationMs,
          carrierId: id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir le Porteur')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  )
                : Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          "Touche l'objet (A, B ou C) qui contient l'élément caché.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _frameWidth / _frameHeight,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Facteur d'échelle entre la résolution d'analyse
                                // (480px de large) et la taille réellement affichée
                                // à l'écran, pour que les zones tactiles tombent
                                // exactement sur les objets dessinés.
                                final scaleX = constraints.maxWidth / _frameWidth;
                                final scaleY = constraints.maxHeight / _frameHeight;

                                return Stack(
                                  children: [
                                    Image.memory(_frameJpeg!, fit: BoxFit.fill),
                                    for (final o in _objects)
                                      Positioned(
                                        left: o.box.left * scaleX,
                                        top: o.box.top * scaleY,
                                        width: o.box.width * scaleX,
                                        height: o.box.height * scaleY,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _selectCarrier(o.id),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.white24,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
