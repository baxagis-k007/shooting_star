import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../vision/object_tracker.dart';

// Étape 7 : dernière étape de la routine. On réutilise directement la
// dernière frame déjà analysée et les positions déjà connues des 3 objets
// (aucun nouveau décodage vidéo, aucun nouveau calcul de détection --
// c'est juste de l'affichage + une comparaison de booléen).
class FinalVerificationScreen extends StatefulWidget {
  final Uint8List frameJpeg;
  final int frameWidth;
  final int frameHeight;
  final List<Track> tracks;

  const FinalVerificationScreen({
    super.key,
    required this.frameJpeg,
    required this.frameWidth,
    required this.frameHeight,
    required this.tracks,
  });

  @override
  State<FinalVerificationScreen> createState() => _FinalVerificationScreenState();
}

class _FinalVerificationScreenState extends State<FinalVerificationScreen> {
  String? _selectedId;
  bool? _success;

  void _select(Track track) {
    setState(() {
      _selectedId = track.id;
      // La comparaison se fait sur `isCarrier` (l'objet physique verrouillé
      // depuis l'Étape 4), pas sur un label -- fiable même si la routine a
      // relabellisé les objets en cours de route (Étape 5).
      _success = track.isCarrier;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification finale')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Touche l'objet qui a révélé l'élément caché.",
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.frameWidth / widget.frameHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaleX = constraints.maxWidth / widget.frameWidth;
                      final scaleY = constraints.maxHeight / widget.frameHeight;

                      return Stack(
                        children: [
                          Image.memory(widget.frameJpeg, fit: BoxFit.fill),
                          for (final t in widget.tracks)
                            Positioned(
                              left: t.box.left * scaleX,
                              top: t.box.top * scaleY,
                              width: t.box.width * scaleX,
                              height: t.box.height * scaleY,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _select(t),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: _selectedId == t.id
                                          ? Colors.white
                                          : Colors.white24,
                                      width: _selectedId == t.id ? 3 : 1,
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

            // Résultat affiché juste après la sélection.
            if (_success != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      _success! ? Icons.check_circle : Icons.cancel,
                      color: _success! ? Colors.greenAccent : Colors.redAccent,
                      size: 56,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _success! ? 'Suivi réussi' : 'Trace perdue',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _success! ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Objet sélectionné : $_selectedId',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
