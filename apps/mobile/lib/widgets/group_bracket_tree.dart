import "async_view.dart";
import "ornate_frame.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../core/iterable_x.dart";
import "../domain/event_status.dart";
import "../features/bracket/bracket_provider.dart";
import "../features/next_match/next_match_screen.dart";
import "../theme/tokens.dart";

/// Arbre d'une poule GSL (Ouverture → Vainqueurs/Élimination → Decider →
/// Qualifiés), façon VLR.gg mais adapté au mobile : colonnes défilables à
/// l'horizontale (comme la frise de saison) plutôt que côte à côte sur tout
/// l'écran, et sans logo d'équipe — `BracketParticipantDto` n'en porte pas,
/// contrairement à `EventParticipantDto` (limite déjà présente sur l'arbre
/// radial et le repêchage, pas propre à ce widget). Réutilisé par l'onglet
/// Groupes (`BracketScreen`) et la carte "Maintenant" de l'écran Saison — un
/// seul arbre plutôt que deux rendus différents du même bracket.
class GroupBracketTree extends ConsumerWidget {
  const GroupBracketTree({super.key, required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(competitionDetailProvider(competitionId)).value?.name ?? "";
    final bracket = ref.watch(bracketProvider(competitionId));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: OrnateFrame(
        radius: AppRadii.chip,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip)),
          child: switch (bracket) {
            _ when bracket.hasValue => _Tree(name: name, bracket: bracket.value!),
            AsyncError() => ErrorState(message: "Poule indisponible.", compact: true, onRetry: () => ref.invalidate(bracketProvider(competitionId))),
            _ => const Skeleton(height: 120, radius: AppRadii.chip),
          },
        ),
      ),
    );
  }
}

// Forme figée d'une poule GSL (2 CLAUDE.md règle 3 : pas de champ dédié en
// base, on la retrouve par la topologie des liens déjà calculés au J5).
class _GslShape {
  const _GslShape({required this.opening1, required this.opening2, required this.winners, required this.elimination, required this.decider});

  final BracketNodeDto opening1;
  final BracketNodeDto opening2;
  final BracketNodeDto winners;
  final BracketNodeDto elimination;
  final BracketNodeDto decider;
}

// `null` si la poule n'a pas exactement cette forme (5 matchs, 2×2×1 par
// round) : l'arbre replié s'affiche seulement quand on est sûr de bien
// nommer chaque case, sinon on retombe sur la liste simple.
_GslShape? _detectGslShape(BracketResponseDto bracket) {
  final byRound = <int, List<BracketNodeDto>>{};
  for (final n in bracket.nodes) {
    byRound.putIfAbsent(n.round.toInt(), () => []).add(n);
  }
  final opening = byRound[2];
  final middle = byRound[1];
  final decider = byRound[0];
  if (opening?.length != 2 || middle?.length != 2 || decider?.length != 1 || byRound.length != 3) return null;

  final deciderNode = decider!.single;
  // "Vainqueurs" envoie son PERDANT au Decider ; "Élimination" y envoie son
  // GAGNANT — seule façon de les distinguer, PandaScore ne donne pas de rôle
  // explicite par match (`docs/01`).
  final winners = middle!.where((n) => bracket.links.any((l) => l.fromEventId == n.eventId && l.toEventId == deciderNode.eventId && l.outcome == "loser"));
  final elimination =
      middle.where((n) => bracket.links.any((l) => l.fromEventId == n.eventId && l.toEventId == deciderNode.eventId && l.outcome == "winner"));
  if (winners.length != 1 || elimination.length != 1) return null;

  return _GslShape(opening1: opening![0], opening2: opening[1], winners: winners.single, elimination: elimination.single, decider: deciderNode);
}

class _Tree extends StatelessWidget {
  const _Tree({required this.name, required this.bracket});

  final String name;
  final BracketResponseDto bracket;

  @override
  Widget build(BuildContext context) {
    final shape = _detectGslShape(bracket);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        shape != null ? _FunnelTree(bracket: bracket, shape: shape) : _SimpleList(bracket: bracket),
      ],
    );
  }
}

// Repli pour une poule qui ne suit pas la forme GSL standard (données
// partielles, format différent) : la même liste qu'avant, un match après
// l'autre, sans les traits de raccordement.
class _SimpleList extends StatelessWidget {
  const _SimpleList({required this.bracket});
  final BracketResponseDto bracket;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final n in bracket.nodes) n.eventId: n};
    final incomingByTarget = <String, List<BracketLinkDto>>{};
    for (final l in bracket.links) {
      incomingByTarget.putIfAbsent(l.toEventId, () => []).add(l);
    }
    final byRound = <int, List<BracketNodeDto>>{};
    for (final n in bracket.nodes) {
      byRound.putIfAbsent(n.round.toInt(), () => []).add(n);
    }
    final rounds = byRound.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in rounds)
          for (final node in byRound[round]!)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _MatchBox(node: node, incoming: incomingByTarget[node.eventId] ?? const [], byId: byId, width: null),
            ),
      ],
    );
  }
}

const _boxW = 132.0;
const _boxH = 52.0;
const _colGap = 40.0;
const _rowGap = 14.0;

// 3 colonnes : Ouverture 1/Ouverture 2/Élimination empilées dans la 1ʳᵉ,
// Vainqueurs/Decider (décalées vers le bas — effet pyramide) dans la 2e,
// une seule case Qualifiés dans la 3e.
const _colX = [0.0, _boxW + _colGap, 2 * (_boxW + _colGap)];
const _opening1Y = 0.0;
const _opening2Y = _boxH + _rowGap;
const _eliminationY = 2 * (_boxH + _rowGap);
// Effet pyramide : la colonne Vainqueurs/Decider démarre plus bas que la
// colonne Ouverture, et se termine plus haut — elle "rentre" dans la forme
// au lieu de rester alignée en haut comme la 1ʳᵉ colonne.
const _staggerY = (_boxH + _rowGap) / 2;
const _winnersY = _staggerY;
const _deciderY = _staggerY + _boxH + _rowGap;
const _totalWidth = 3 * _boxW + 2 * _colGap;
const _totalHeight = _eliminationY + _boxH;
const _qualifiedY = (_winnersY + _deciderY) / 2;

/// L'arbre qui "se réduit" (2 matchs → 1 → 1 → qualifiés), traits compris —
/// géométrie fixe (les 5 cases d'une poule GSL sont toujours à la même
/// place), donc les traits se calculent sans mesurer le rendu réel des
/// cases, contrairement à `BracketPainter` (arbre radial, forme variable).
class _FunnelTree extends StatelessWidget {
  const _FunnelTree({required this.bracket, required this.shape});

  final BracketResponseDto bracket;
  final _GslShape shape;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final n in bracket.nodes) n.eventId: n};
    final incomingByTarget = <String, List<BracketLinkDto>>{};
    for (final l in bracket.links) {
      incomingByTarget.putIfAbsent(l.toEventId, () => []).add(l);
    }
    BracketParticipantDto? winnerOf(BracketNodeDto n) => n.participants.where((p) => p.isWinner == true).firstOrNull;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _totalWidth,
        height: _totalHeight,
        child: Stack(
          children: [
            CustomPaint(size: const Size(_totalWidth, _totalHeight), painter: _FunnelPainter(bracket: bracket, shape: shape)),
            Positioned(left: _colX[0], top: _opening1Y, child: _MatchBox(node: shape.opening1, incoming: const [], byId: byId, width: _boxW)),
            Positioned(left: _colX[0], top: _opening2Y, child: _MatchBox(node: shape.opening2, incoming: const [], byId: byId, width: _boxW)),
            Positioned(
              left: _colX[0],
              top: _eliminationY,
              child: _MatchBox(node: shape.elimination, incoming: incomingByTarget[shape.elimination.eventId] ?? const [], byId: byId, width: _boxW),
            ),
            Positioned(
              left: _colX[1],
              top: _winnersY,
              child: _MatchBox(node: shape.winners, incoming: incomingByTarget[shape.winners.eventId] ?? const [], byId: byId, width: _boxW),
            ),
            Positioned(
              left: _colX[1],
              top: _deciderY,
              child: _MatchBox(node: shape.decider, incoming: incomingByTarget[shape.decider.eventId] ?? const [], byId: byId, width: _boxW),
            ),
            Positioned(
              left: _colX[2],
              top: _qualifiedY,
              child: _QualifiedBox(participants: [winnerOf(shape.winners), winnerOf(shape.decider)]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Traits en coude (horizontal-vertical-horizontal), comme sur VLR.gg — pas
/// de courbe, juste des angles droits. Uniquement le chemin des GAGNANTS :
/// pas de trait vers l'Élimination (son perdant continue vers le Decider,
/// mais rien ne montre d'où viennent ses joueurs — ça ne fait que la moitié
/// du bracket, exprès).
class _FunnelPainter extends CustomPainter {
  _FunnelPainter({required this.bracket, required this.shape});

  final BracketResponseDto bracket;
  final _GslShape shape;

  static const _lineColor = Color(0x26FFFFFF); // blanc 15 %

  void _elbow(Canvas canvas, Paint paint, Offset from, Offset to) {
    final midX = from.dx + (to.dx - from.dx) / 2;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(midX, from.dy)
      ..lineTo(midX, to.dy)
      ..lineTo(to.dx, to.dy);
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    Offset rightOf(double colX, double topY) => Offset(colX + _boxW, topY + _boxH / 2);
    Offset leftOf(double colX, double topY) => Offset(colX, topY + _boxH / 2);

    // Position (colonne, haut) de chaque case connue — sert à retrouver où
    // partent les liens "winner" sans deviner leur sens depuis la forme.
    final position = {
      shape.opening1.eventId: (_colX[0], _opening1Y),
      shape.opening2.eventId: (_colX[0], _opening2Y),
      shape.elimination.eventId: (_colX[0], _eliminationY),
      shape.winners.eventId: (_colX[1], _winnersY),
      shape.decider.eventId: (_colX[1], _deciderY),
    };

    // Un seul trait par match : vers l'endroit où va son GAGNANT (jamais son
    // perdant). Ouverture 1/2 → Vainqueurs, Élimination → Decider — trouvés
    // dans les vrais liens plutôt que supposés par position, au cas où.
    for (final link in bracket.links) {
      if (link.outcome != "winner") continue;
      final from = position[link.fromEventId];
      final to = position[link.toEventId];
      if (from == null || to == null) continue;
      _elbow(canvas, paint, rightOf(from.$1, from.$2), leftOf(to.$1, to.$2));
    }
    // Qualifiés : le gagnant de Vainqueurs se qualifie directement, celui du
    // Decider aussi — deux fins de chemin gagnant, pas des liens de la base.
    _elbow(canvas, paint, rightOf(_colX[1], _winnersY), leftOf(_colX[2], _qualifiedY));
    _elbow(canvas, paint, rightOf(_colX[1], _deciderY), leftOf(_colX[2], _qualifiedY));
  }

  @override
  bool shouldRepaint(covariant _FunnelPainter oldDelegate) => oldDelegate.bracket != bracket;
}

class _QualifiedBox extends StatelessWidget {
  const _QualifiedBox({required this.participants});
  final List<BracketParticipantDto?> participants;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _boxW,
      height: _boxH,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.surfaceBorder)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in participants)
            Text(
              p?.shortName ?? p?.name ?? "?",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p != null ? AppColors.win : AppColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _MatchBox extends StatelessWidget {
  const _MatchBox({required this.node, required this.incoming, required this.byId, required this.width});

  final BracketNodeDto node;
  final List<BracketLinkDto> incoming;
  final Map<String, BracketNodeDto> byId;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final rows = bracketMatchRows(node, incoming, byId);
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: node.eventId))),
        child: Container(
          width: width,
          height: width != null ? _boxH : null,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: node.status.statusKind == EventStatusKind.live ? AppColors.live : AppColors.surfaceBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, score, isWinner) in rows)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isWinner ? AppColors.win : AppColors.textSecondary,
                          fontWeight: isWinner ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (score != null) Text(score, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
