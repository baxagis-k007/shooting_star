import 'package:image/image.dart' as img;

// Rectangle simple en entiers (on évite dart:ui.Rect pour rester
// indépendant de Flutter dans ce fichier — juste un besoin de coordonnées).
class IntRect {
  final int left, top, width, height;
  const IntRect(this.left, this.top, this.width, this.height);
}

// Un objet détecté avec son ID temporaire (A, B, C).
class DetectedObject {
  final String id;
  final IntRect box;
  final int area;
  const DetectedObject({required this.id, required this.box, required this.area});
}

/// Détecteur "maison" en Dart pur, volontairement simple :
/// 1. Seuillage (les objets sont supposés plus SOMBRES que le fond)
/// 2. Étiquetage des composantes connexes (flood fill itératif, sans récursion
///    pour ne jamais faire exploser la pile d'appels sur un CPU faible)
/// 3. On garde les 3 plus grands blobs -> objets A, B, C (triés de gauche à droite)
///
/// Pas de réseau de neurones, pas de bibliothèque native : tout tourne dans
/// de simples tableaux d'octets, ce qui reste très léger en RAM même sur
/// un appareil d'entrée de gamme.
class SimpleObjectDetector {
  /// Luminosité (0-255) en dessous de laquelle un pixel est considéré
  /// comme faisant partie d'un objet. À ajuster selon l'éclairage/fond réel.
  final int threshold;

  /// Aire minimale (en pixels, sur l'image redimensionnée) pour qu'un blob
  /// soit considéré comme un objet et non du bruit.
  final int minArea;

  /// Largeur max de traitement : on downscale toujours l'image avant analyse
  /// pour garder un temps de calcul et une empreinte mémoire faibles.
  final int maxWidth;

  const SimpleObjectDetector({
    this.threshold = 100,
    this.minArea = 200,
    this.maxWidth = 480,
  });

  List<DetectedObject> detect(img.Image original) {
    // 1. Downscale si nécessaire (image package : copyResize)
    final img.Image resized = original.width > maxWidth
        ? img.copyResize(original, width: maxWidth)
        : original;

    // 2. Niveaux de gris : un seul canal à comparer, plus simple et plus léger
    final img.Image gray = img.grayscale(resized);
    final int w = gray.width;
    final int h = gray.height;

    // "visited" : un seul octet par pixel, suffisant et compact
    final visited = List<bool>.filled(w * h, false);
    final List<DetectedObject> blobs = [];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int idx = y * w + x;
        if (visited[idx]) continue;

        final int lum = gray.getPixel(x, y).r.toInt();
        if (lum >= threshold) {
          // Pixel de fond : on le marque visité et on passe au suivant
          visited[idx] = true;
          continue;
        }

        // 3. Flood fill itératif (pile explicite, pas de récursion)
        final List<int> stack = [idx];
        visited[idx] = true;
        int minX = x, maxX = x, minY = y, maxY = y, area = 0;

        while (stack.isNotEmpty) {
          final int cur = stack.removeLast();
          final int cx = cur % w;
          final int cy = cur ~/ w;
          area++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;

          // 4 voisins (haut/bas/gauche/droite) : suffisant pour ce cas d'usage
          const offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)];
          for (final (dx, dy) in offsets) {
            final int nx = cx + dx;
            final int ny = cy + dy;
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            final int nidx = ny * w + nx;
            if (visited[nidx]) continue;

            if (gray.getPixel(nx, ny).r.toInt() < threshold) {
              visited[nidx] = true;
              stack.add(nidx);
            } else {
              visited[nidx] = true; // fond : marqué visité pour ne pas le rescanner
            }
          }
        }

        if (area >= minArea) {
          blobs.add(DetectedObject(
            id: '', // attribué plus bas
            box: IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1),
            area: area,
          ));
        }
      }
    }

    // On ne garde que les 3 plus grands blobs (les 3 objets attendus).
    blobs.sort((a, b) => b.area.compareTo(a.area));
    final top3 = blobs.take(3).toList();

    // ID temporaire A/B/C attribué par position gauche -> droite.
    // (Les objets étant quasi identiques, on ne peut pas les distinguer
    // par leur apparence : la position sert de repère temporaire.)
    top3.sort((a, b) => a.box.left.compareTo(b.box.left));

    const labels = ['A', 'B', 'C'];
    return [
      for (int i = 0; i < top3.length; i++)
        DetectedObject(id: labels[i], box: top3[i].box, area: top3[i].area),
    ];
  }
}
