import "dart:math" as math;
import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/iterable_x.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";

/// Arbre radial (écran 02/07, `docs/02`) : la finale est au centre, les tours
/// précédents s'étalent sur des anneaux vers l'extérieur — `round` (calculé
/// côté API, `packages/domain`) fixe l'anneau. L'angle dans un anneau, lui,
/// est réparti ici : chaque nœud hérite de l'angle moyen des matchs qui le
/// nourrissent, pour que les branches se suivent visuellement (ponytail :
/// pas de vrai calcul de slot croisé haut/bas tableau, cf. `packages/domain/bracket.ts`).
class BracketPainter extends CustomPainter {
  BracketPainter({required this.nodes, required this.links, required this.highlightedEventIds});

  final List<BracketNodeDto> nodes;
  final List<BracketLinkDto> links;
  final Set<String> highlightedEventIds;

  ({Map<String, Offset> positions, double centerRadius}) _computePositions(Offset center, Size size) {
    // `round` est un `num` côté client généré (OpenAPI `number`, packages/api_client_dart) :
    // toujours un entier en pratique, ramené à `int` ici pour indexer les anneaux.
    final byRound = <int, List<BracketNodeDto>>{};
    for (final n in nodes) {
      byRound.putIfAbsent(n.round.toInt(), () => []).add(n);
    }
    if (byRound.isEmpty) return (positions: {}, centerRadius: 0);
    final maxRound = byRound.keys.reduce(math.max);

    // Les anneaux se partagent l'espace disponible : le premier tour n'est
    // jamais collé au centre, le tour le plus profond n'est jamais coupé —
    // quel que soit le nombre de tours ou la taille de l'écran.
    final maxRadius = math.min(size.width, size.height) / 2;
    final centerRadius = maxRadius / (maxRound + 2);
    final ringGap = centerRadius;

    final childrenOf = <String, List<String>>{};
    for (final l in links) {
      childrenOf.putIfAbsent(l.toEventId, () => []).add(l.fromEventId);
    }

    final angles = <String, double>{};
    for (var round = maxRound; round >= 1; round--) {
      final ring = byRound[round] ?? const <BracketNodeDto>[];
      final withAngle = <BracketNodeDto>[];
      final withoutAngle = <BracketNodeDto>[];
      for (final node in ring) {
        final childAngles = (childrenOf[node.eventId] ?? const []).map((id) => angles[id]).whereType<double>().toList();
        if (childAngles.isNotEmpty) {
          angles[node.eventId] = childAngles.reduce((a, b) => a + b) / childAngles.length;
          withAngle.add(node);
        } else {
          withoutAngle.add(node);
        }
      }
      // Répartit les nœuds sans enfant connu (feuilles du tour le plus profond,
      // ou bracket incomplet) sur les créneaux angulaires restants.
      if (withoutAngle.isNotEmpty) {
        final total = ring.length;
        var slot = 0;
        for (final node in ring) {
          if (angles.containsKey(node.eventId)) continue;
          angles[node.eventId] = 2 * math.pi * slot / total;
          slot++;
        }
      }
    }

    final positions = <String, Offset>{};
    for (var round = 1; round <= maxRound; round++) {
      final radius = centerRadius + round * ringGap;
      for (final node in byRound[round] ?? const <BracketNodeDto>[]) {
        final angle = angles[node.eventId] ?? 0;
        positions[node.eventId] = center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      }
    }
    for (final node in byRound[0] ?? const <BracketNodeDto>[]) {
      positions[node.eventId] = center;
    }
    return (positions: positions, centerRadius: centerRadius);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final (:positions, :centerRadius) = _computePositions(center, size);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.surfaceBorder;
    final goldLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.gold;

    for (final link in links) {
      final from = positions[link.fromEventId];
      final to = positions[link.toEventId];
      if (from == null || to == null) continue;
      final highlighted = highlightedEventIds.contains(link.fromEventId) && highlightedEventIds.contains(link.toEventId);
      canvas.drawLine(from, to, highlighted ? goldLinePaint : linePaint);
    }

    for (final node in nodes) {
      final pos = positions[node.eventId];
      if (pos == null) continue;
      if (node.round == 0) {
        _paintCenter(canvas, pos, node, centerRadius);
      } else {
        _paintNode(canvas, pos, node, highlightedEventIds.contains(node.eventId));
      }
    }
  }

  void _paintCenter(Canvas canvas, Offset pos, BracketNodeDto node, double radius) {
    final finished = node.status.statusKind == EventStatusKind.finished;
    canvas.drawCircle(
      pos,
      radius,
      Paint()..color = finished ? AppColors.gold.withValues(alpha: 0.15) : AppColors.surface,
    );
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = finished ? AppColors.gold : AppColors.surfaceBorder,
    );
    final winner = node.participants.where((p) => p.isWinner == true).map((p) => p.shortName ?? p.name).firstOrNull;
    _paintLabel(canvas, pos, winner ?? "?", finished ? AppColors.gold : AppColors.textSecondary);
  }

  void _paintNode(Canvas canvas, Offset pos, BracketNodeDto node, bool highlighted) {
    final isLive = node.status.statusKind == EventStatusKind.live;
    const radius = 20.0;
    canvas.drawCircle(pos, radius, Paint()..color = AppColors.surface);
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isLive ? 2.5 : (highlighted ? 2.5 : 1.5)
        ..color = isLive ? AppColors.live : (highlighted ? AppColors.gold : AppColors.surfaceBorder),
    );
    final label = node.participants.isEmpty
        ? "TBD"
        : node.participants.map((p) => p.shortName ?? p.name.substring(0, math.min(3, p.name.length))).join("/");
    _paintLabel(canvas, pos, label, highlighted ? AppColors.gold : AppColors.textPrimary);
  }

  void _paintLabel(Canvas canvas, Offset pos, String text, Color color) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 60);
    painter.paint(canvas, pos - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant BracketPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.links != links || oldDelegate.highlightedEventIds != highlightedEventIds;
  }
}
