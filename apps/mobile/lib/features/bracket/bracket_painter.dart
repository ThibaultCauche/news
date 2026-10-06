import "dart:math" as math;
import "package:flutter/material.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "bracket_model.dart";

/// Géométrie de l'arbre radial : partagée par le dessin et par la détection des appuis.
class RadialLayout {
  // Quatre anneaux (phase finale avec repêchage) : des cercles plus petits pour que deux anneaux voisins ne se chevauchent pas.
  RadialLayout(this.tree, Size size) : slotRadius = tree.rings >= 4 ? 16.0 : 19.0 {
    center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - slotRadius - 4;
    centerRadius = maxRadius * (tree.rings >= 4 ? 0.24 : 0.30);
    _span = maxRadius - centerRadius;
  }

  final double slotRadius;

  final RadialTree tree;
  late final Offset center;
  late final double centerRadius;
  late final double _span;

  /// Rayon de l'anneau [ring] ; [branchRings] : le nombre d'anneaux de la moitié du cercle (0 = tout l'arbre).
  double ringRadius(int ring, [int branchRings = 0]) {
    final rings = branchRings > 0 ? branchRings : tree.rings;
    return rings == 0 ? centerRadius : centerRadius + ring * _span / rings;
  }

  Offset polar(double radius, double angle) => center + Offset(radius * math.cos(angle), radius * math.sin(angle));

  Offset position(TreeSlot slot) => polar(ringRadius(slot.ring, slot.branchRings), slot.angle);

  /// Le match sous un appui : un cercle d'équipe → son match ; le centre → le match décisif.
  String? matchAt(Offset point) {
    final hit = tree.slots.where((s) => !s.hidden && (position(s) - point).distance <= slotRadius + 8).toList()
      ..sort((a, b) => (position(a) - point).distance.compareTo((position(b) - point).distance));
    if (hit.isNotEmpty) return hit.first.matchId;
    if ((point - center).distance <= centerRadius) return tree.center?.eventId;
    return null;
  }
}

/// Arbre radial (écrans 02/07, `docs/02`) : une équipe par cercle, les 8 équipes des quarts
/// à l'extérieur, le match décisif au centre. Le contenu du centre (compte à rebours,
/// champion) est un widget posé par-dessus (`bracket_screen.dart`). Pas d'animation :
/// règle 13 de `CLAUDE.md`.
class BracketPainter extends CustomPainter {
  BracketPainter({required this.tree, required this.followedEntityIds, this.divider});

  final RadialTree tree;
  final Set<String> followedEntityIds;

  /// Une ligne horizontale qui coupe le cercle en deux (poules : ouvertures en haut, élimination en
  /// bas), avec le nom de chaque moitié. Remplace alors les étiquettes d'anneaux.
  final ({String top, String bottom})? divider;

  bool _followed(TreeSlot? s) => s?.team != null && followedEntityIds.contains(s!.team!.entityId);

  @override
  void paint(Canvas canvas, Size size) {
    final layout = RadialLayout(tree, size);
    final center = layout.center;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.surfaceBorder;
    if (divider == null) {
      for (var ring = 1; ring <= tree.rings; ring++) {
        canvas.drawCircle(center, layout.ringRadius(ring), ringPaint);
      }
    } else {
      // Cercle coupé en deux : chaque moitié a ses propres anneaux, répartis sur tout le rayon.
      for (final (slots, from) in [(tree.slots.where((s) => s.angle < 0).toList(), -math.pi), (tree.slots.where((s) => s.angle >= 0).toList(), 0.0)]) {
        final rings = slots.map((s) => s.branchRings > 0 ? s.branchRings : s.ring).fold(0, math.max);
        for (var ring = 1; ring <= rings; ring++) {
          canvas.drawArc(Rect.fromCircle(center: center, radius: layout.ringRadius(ring, rings)), from, math.pi, false, ringPaint);
        }
      }
    }
    if (divider == null) {
      for (final entry in tree.ringLabels.entries) {
        _paintRingLabel(canvas, Offset(center.dx, center.dy - layout.ringRadius(entry.key)), entry.value);
      }
    } else {
      _paintDivider(canvas, layout, divider!);
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.textTertiary;
    final goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.gold;
    final centerFollowed = tree.center?.participants.any((p) => followedEntityIds.contains(p.entityId)) ?? false;
    final brassPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.brass;
    final brassPaths = <Path>[];
    final goldPaths = <Path>[];
    for (final slot in tree.slots.where((s) => !s.hidden)) {
      final path = _link(layout, slot);
      final parent = slot.parent;
      final gold = _followed(slot) && (parent == null ? centerFollowed : parent.team?.entityId == slot.team!.entityId);
      if (gold) {
        goldPaths.add(path);
      } else if (slot.advances) {
        brassPaths.add(path); // le chemin de l'équipe qui avance, en laiton
      } else {
        canvas.drawPath(path, linePaint);
      }
    }
    for (final path in brassPaths) {
      canvas.drawPath(path, brassPaint);
    }
    for (final path in goldPaths) {
      canvas.drawPath(path, goldPaint);
    }

    _paintCenter(canvas, layout);
    for (final slot in tree.slots.where((s) => !s.hidden)) {
      _paintSlot(canvas, layout.position(slot), slot, layout.slotRadius);
    }
  }

  /// Du cercle vers son parent : radial, arc de cercle à mi-chemin entre les deux anneaux,
  /// radial. Le dernier anneau rejoint le centre tout droit.
  Path _link(RadialLayout layout, TreeSlot slot) {
    final path = Path()..moveTo(layout.position(slot).dx, layout.position(slot).dy);
    final parent = slot.parent;
    if (parent == null) {
      // Anneau 1 : la barre entre les deux équipes du match, à mi-chemin du centre, puis le chemin vers lui.
      final siblings = tree.slots.where((s) => s.parent == null && s.matchId == slot.matchId).toList();
      final target = siblings.map((s) => s.angle).reduce((a, b) => a + b) / siblings.length;
      // Deux équipes aux antipodes (finale du haut, à gauche et à droite) : un arc de demi-cercle
      // serait absurde, chacune rejoint le centre tout droit.
      if ((slot.angle - target).abs() > math.pi / 3) {
        final end = layout.polar(layout.centerRadius, slot.angle);
        return path..lineTo(end.dx, end.dy);
      }
      final mid = (layout.ringRadius(1, slot.branchRings) + layout.centerRadius) / 2;
      final start = layout.polar(mid, slot.angle);
      final end = layout.polar(layout.centerRadius, target);
      return path
        ..lineTo(start.dx, start.dy)
        ..arcTo(Rect.fromCircle(center: layout.center, radius: mid), slot.angle, target - slot.angle, false)
        ..lineTo(end.dx, end.dy);
    }
    final mid = (layout.ringRadius(slot.ring, slot.branchRings) + layout.ringRadius(parent.ring, parent.branchRings)) / 2;
    final start = layout.polar(mid, slot.angle);
    final end = layout.position(parent);
    return path
      ..lineTo(start.dx, start.dy)
      ..arcTo(Rect.fromCircle(center: layout.center, radius: mid), slot.angle, parent.angle - slot.angle, false)
      ..lineTo(end.dx, end.dy);
  }

  void _paintCenter(Canvas canvas, RadialLayout layout) {
    final node = tree.center;
    final finished = node?.status.statusKind == EventStatusKind.finished;
    final live = node?.status.statusKind == EventStatusKind.live;
    canvas.drawCircle(layout.center, layout.centerRadius, Paint()..color = finished ? AppColors.win.withValues(alpha: 0.15) : AppColors.surface);
    canvas.drawCircle(
      layout.center,
      layout.centerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = live ? 2.5 : 2
        ..color = live ? AppColors.live : (finished ? AppColors.win : AppColors.surfaceBorderHighlight),
    );
  }

  void _paintSlot(Canvas canvas, Offset pos, TreeSlot slot, double radius) {
    final unknown = slot.team == null;
    final followed = _followed(slot);
    // Fond un peu plus clair que la carte : un logo sombre s'y lit (comme dans la pyramide).
    canvas.drawCircle(pos, radius, Paint()..color = Color.alphaBlend(AppColors.surfaceBorder, AppColors.surface));

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = followed || slot.live || slot.won ? 2.5 : 1.5
      ..color = slot.live ? AppColors.live : (followed ? AppColors.gold : (slot.won ? AppColors.brass : AppColors.surfaceBorderHighlight));
    if (unknown) {
      _dashedCircle(canvas, pos, radius, border);
    } else {
      canvas.drawCircle(pos, radius, border);
    }
  }

  void _dashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), i * sweep, sweep * 0.55, false, paint);
    }
  }

  void _paintRingLabel(Canvas canvas, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: AppColors.textTertiary, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: at, width: painter.width + 8, height: painter.height + 2);
    canvas.drawRect(rect, Paint()..color = AppColors.background);
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  void _paintDivider(Canvas canvas, RadialLayout layout, ({String top, String bottom}) labels) {
    final reach = layout.ringRadius(tree.rings) + layout.slotRadius;
    final y = layout.center.dy;
    canvas.drawLine(
      Offset(layout.center.dx - reach, y),
      Offset(layout.center.dx + reach, y),
      Paint()
        ..strokeWidth = 1
        ..color = AppColors.brass.withValues(alpha: 0.45),
    );
    if (labels.top.isNotEmpty) _paintDividerLabel(canvas, Offset(layout.center.dx - reach + 2, y - 8), labels.top, above: true);
    if (labels.bottom.isNotEmpty) _paintDividerLabel(canvas, Offset(layout.center.dx - reach + 2, y + 8), labels.bottom, above: false);
  }

  void _paintDividerLabel(Canvas canvas, Offset anchor, String text, {required bool above}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: AppColors.brass, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = anchor + Offset(0, above ? -painter.height / 2 : painter.height / 2);
    canvas.drawRect(Rect.fromCenter(center: at + Offset(painter.width / 2, 0), width: painter.width + 8, height: painter.height + 2), Paint()..color = AppColors.surface);
    painter.paint(canvas, at - Offset(0, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant BracketPainter oldDelegate) => oldDelegate.tree != tree || oldDelegate.followedEntityIds != followedEntityIds;
}
