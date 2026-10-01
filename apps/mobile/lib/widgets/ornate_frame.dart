import "package:flutter/material.dart";
import "../theme/tokens.dart";

/// Matchs à enjeu (finale, élimination, décisif) : cadre renforcé.
/// ponytail: simple lecture du nom du match, à remplacer par un champ API si les noms varient trop.
bool isHighStakes(String eventName) => RegExp("final|elimination|decider|décisif", caseSensitive: false).hasMatch(eventName);

/// Cadre fin à pointes (J16) : un filet laiton de 0,8 px, des angles marqués
/// dont les branches s'effilent en pointe, un petit losange au milieu des
/// côtés haut et bas. [strong] (grandes finales, éliminations) renforce le trait
/// et ajoute un second filet intérieur. Dessiné par-dessus l'enfant, sans
/// toucher à sa mise en page ni intercepter les appuis.
class OrnateFrame extends StatelessWidget {
  const OrnateFrame({super.key, required this.child, this.radius = AppRadii.card, this.strong = false, this.color = AppColors.brass});

  final Widget child;
  final double radius;
  final bool strong;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(foregroundPainter: _FramePainter(radius, strong, color), child: child);
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.radius, this.strong, this.color);

  final double radius;
  final bool strong;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final w = size.width, h = size.height;
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withValues(alpha: strong ? 0.55 : 0.32);
    canvas.drawRRect(RRect.fromLTRBR(0.4, 0.4, w - 0.4, h - 0.4, Radius.circular(r)), hair);

    // Angles : arc épais, puis deux branches qui s'effilent le long des côtés.
    final bright = color.withValues(alpha: strong ? 1 : 0.85);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strong ? 1.8 : 1.4
      ..color = bright;
    final fill = Paint()..color = bright;
    final tail = (strong ? 44.0 : 34.0).clamp(0.0, (w - 2 * r) / 2).clamp(0.0, size.shortestSide * 0.3);
    final t = strong ? 2.4 : 2.0;
    for (final (cx, cy, sx, sy) in [(0.0, 0.0, 1.0, 1.0), (w, 0.0, -1.0, 1.0), (0.0, h, 1.0, -1.0), (w, h, -1.0, -1.0)]) {
      final rect = Rect.fromLTWH(cx == 0 ? 0 : w - 2 * r, cy == 0 ? 0 : h - 2 * r, 2 * r, 2 * r);
      final start = sx > 0 ? (sy > 0 ? 3.1416 : 1.5708) : (sy > 0 ? -1.5708 : 0.0);
      canvas.drawArc(rect.deflate(0.7), start, 1.5708, false, arc);
      for (final horizontal in [true, false]) {
        final p = Path();
        if (horizontal) {
          final x0 = cx + sx * r, x1 = cx + sx * (r + tail);
          p
            ..moveTo(x0, cy + sy * (t / 2 - 0.6))
            ..lineTo(x1, cy + sy * 0.4)
            ..lineTo(x0, cy + sy * (t + 0.2))
            ..close();
        } else {
          final y0 = cy + sy * r, y1 = cy + sy * (r + tail);
          p
            ..moveTo(cx + sx * (t / 2 - 0.6), y0)
            ..lineTo(cx + sx * 0.4, y1)
            ..lineTo(cx + sx * (t + 0.2), y0)
            ..close();
        }
        canvas.drawPath(p, fill);
      }
    }

    // Losanges au milieu des côtés haut et bas.
    final d = strong ? 3.5 : 2.5;
    for (final y in [0.4, h - 0.4]) {
      canvas.drawPath(
        Path()
          ..moveTo(w / 2, y - d)
          ..lineTo(w / 2 + d, y)
          ..lineTo(w / 2, y + d)
          ..lineTo(w / 2 - d, y)
          ..close(),
        Paint()..color = color,
      );
    }

    if (strong) {
      canvas.drawRRect(
        RRect.fromLTRBR(4, 4, w - 4, h - 4, Radius.circular((r - 4).clamp(0, r))),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = color.withValues(alpha: 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.radius != radius || old.strong != strong || old.color != color;
}

/// `Card` entouré d'un [OrnateFrame] (J16) ; [margin] s'applique autour du cadre.
class FramedCard extends StatelessWidget {
  const FramedCard({super.key, this.margin = EdgeInsets.zero, required this.child});

  final EdgeInsetsGeometry margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: OrnateFrame(child: Card(margin: EdgeInsets.zero, child: child)),
    );
  }
}
