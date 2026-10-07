import "dart:math" as math;
import "async_view.dart";
import "ornate_frame.dart";
import "../features/next_match/next_match_screen.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../domain/event_status.dart";
import "../features/bracket/bracket_model.dart";
import "../features/bracket/bracket_provider.dart";
import "../features/bracket/bracket_view.dart";
import "../features/bracket/radial_bracket.dart";
import "../features/bracket/swiss_view.dart";
import "../features/follows/follows_provider.dart";
import "../theme/app_theme.dart";
import "bracket_match_card.dart";
import "horizontal_bracket.dart";
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
  const GroupBracketTree({super.key, required this.competitionId, this.followViewPreference = false});

  final String competitionId;

  /// Vrai sur la page du tableau, où l'on choisit pyramide ou cercle ; la page du jeu garde la pyramide,
  /// bien plus basse que quatre cercles empilés.
  final bool followViewPreference;

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
            _ when bracket.hasValue => _Tree(name: name, bracket: bracket.value!, followViewPreference: followViewPreference, competitionId: competitionId),
            AsyncError() => ErrorState(message: "Poule indisponible.", compact: true, onRetry: () => ref.invalidate(bracketProvider(competitionId))),
            _ => const Skeleton(height: 120, radius: AppRadii.chip),
          },
        ),
      ),
    );
  }
}

// Forme figée d'une poule GSL (règle 3 de CLAUDE.md : pas de champ dédié en base).
class GslShape {
  const GslShape({required this.opening1, required this.opening2, required this.winners, required this.elimination, required this.decider});

  final BracketNodeDto opening1;
  final BracketNodeDto opening2;
  final BracketNodeDto winners;
  final BracketNodeDto elimination;
  final BracketNodeDto decider;
}

/// `null` si la poule n'a pas la forme GSL (5 matchs) : l'arbre replié s'affiche seulement quand on est sûr
/// de bien nommer chaque case, sinon on retombe sur la liste simple.
///
/// Reconnue d'abord **par les noms** (« Winners Match », « Elimination Match », « Decider Match » ; les deux
/// autres matchs sont les ouvertures, dans l'ordre de leur horaire). Les liens ne suffisent pas (J19) : dans les
/// poules de Champions B, C et D, PandaScore ne donne qu'un des deux matchs d'ouverture dans `previous_matches`
/// (4 liens au lieu de 6), et l'arbre retombait sur la liste. Repli sur la topologie des liens (2×2×1 par tour)
/// quand les noms ne sont pas ceux-là.
GslShape? detectGslShape(BracketResponseDto bracket) => _detectByNames(bracket) ?? _detectByLinks(bracket);

GslShape? _detectByNames(BracketResponseDto bracket) {
  if (bracket.nodes.length != 5) return null;
  List<BracketNodeDto> named(RegExp pattern) => bracket.nodes.where((n) => pattern.hasMatch(n.name)).toList();
  final winners = named(RegExp(r"winners?\s+match", caseSensitive: false));
  final elimination = named(RegExp(r"elimination\s+match", caseSensitive: false));
  final decider = named(RegExp(r"decider", caseSensitive: false));
  if (winners.length != 1 || elimination.length != 1 || decider.length != 1) return null;
  final special = {winners.single.eventId, elimination.single.eventId, decider.single.eventId};
  final openings = bracket.nodes.where((n) => !special.contains(n.eventId)).toList()
    ..sort((a, b) => (a.startsAt ?? "").compareTo(b.startsAt ?? ""));
  if (openings.length != 2) return null;
  return GslShape(opening1: openings[0], opening2: openings[1], winners: winners.single, elimination: elimination.single, decider: decider.single);
}

GslShape? _detectByLinks(BracketResponseDto bracket) {
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

  return GslShape(opening1: opening![0], opening2: opening[1], winners: winners.single, elimination: elimination.single, decider: deciderNode);
}

class _Tree extends ConsumerWidget {
  const _Tree({required this.name, required this.bracket, required this.followViewPreference, required this.competitionId});

  final String competitionId;
  final String name;
  final BracketResponseDto bracket;
  final bool followViewPreference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase suisse (J23) : ni poule GSL ni arbre, une colonne par ronde.
    if (bracket.format == "swiss") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.toUpperCase(), style: AppTextStyles.sectionTitle.copyWith(fontSize: 14, color: AppColors.brass)),
          const SizedBox(height: AppSpacing.sm),
          SwissView(bracket: bracket, competitionId: competitionId),
        ],
      );
    }
    final detected = detectGslShape(bracket);
    // PandaScore nomme les ouvertures par leurs équipes (« TYLOO vs G2 ») : on les rebaptise
    // « Ouverture 1/2 » pour que chaque case ait un titre lisible.
    final named = detected == null ? bracket : _withOpeningNames(bracket, detected);
    final shape = detected == null ? null : detectGslShape(named);
    final followed = (ref.watch(followsProvider).value ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    final circle = followViewPreference && ref.watch(bracketViewProvider) == BracketView.circle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.toUpperCase(), style: AppTextStyles.sectionTitle.copyWith(fontSize: 14, color: AppColors.brass)),
        const SizedBox(height: AppSpacing.sm),
        if (shape == null)
          _SimpleList(bracket: bracket)
        else if (circle)
          _GroupCircle(bracket: named, shape: shape, followed: followed)
        else
          HorizontalBracket(
            bracket: named,
            followed: followed,
            // Trois colonnes, comme avant : 3 cases (Ouverture 1, Ouverture 2, Élimination), 2 (Vainqueurs,
            // Décisif, en pyramide), 1 (Qualifiés). Seuls les chemins des gagnants sont tracés.
            layout: GridLayout(cells: [
              GridCell(node: shape.opening1, col: 0, row: 0),
              GridCell(node: shape.opening2, col: 0, row: 1),
              GridCell(node: shape.elimination, col: 0, row: 2),
              GridCell(node: shape.winners, col: 1, row: 0.5),
              GridCell(node: shape.decider, col: 1, row: 1.5),
            ], cols: 2, rows: 3),
            links: [
              (shape.opening1.eventId, shape.winners.eventId),
              (shape.opening2.eventId, shape.winners.eventId),
              (shape.elimination.eventId, shape.decider.eventId),
            ],
            trailing: _QualifiedBox(participants: [winnerOf(shape.winners), winnerOf(shape.decider)]),
            trailingFrom: [shape.winners.eventId, shape.decider.eventId],
          ),
      ],
    );
  }
}

BracketResponseDto _withOpeningNames(BracketResponseDto bracket, GslShape shape) => bracket.rebuild((b) => b
  ..nodes.map((n) => n.eventId == shape.opening1.eventId
      ? n.rebuild((x) => x..name = "Opening Match 1")
      : n.eventId == shape.opening2.eventId
          ? n.rebuild((x) => x..name = "Opening Match 2")
          : n));

/// Le cercle d'une poule : les qualifiés au centre, trois branches autour. Les vainqueurs (deux
/// ouvertures puis le match des vainqueurs) forment la moitié du haut ; l'élimination, qui reprend
/// les perdants des ouvertures, et le match décisif forment la troisième branche, en bas.
class _GroupCircle extends StatelessWidget {
  const _GroupCircle({required this.bracket, required this.shape, required this.followed});

  final BracketResponseDto bracket;
  final GslShape shape;
  final Set<String> followed;

  @override
  Widget build(BuildContext context) {
    final qualified = [winnerOf(shape.winners), winnerOf(shape.decider)];
    // Un « bracket » synthétique pour réutiliser l'arbre radial : seul le centre (round 0) est inventé.
    BracketNodeDto asRound1(BracketNodeDto n) => n.rebuild((b) => b..round = 1);
    final center = shape.decider.rebuild((b) => b
      ..eventId = "qualified"
      ..name = "Qualified"
      ..round = 0
      // Le centre n'est pas le match décisif : il ne prend pas son « en direct » rouge, seulement « terminé » (or) une fois les deux qualifiés connus.
      ..status = qualified.every((q) => q != null) ? "finished" : "scheduled"
      ..participants.replace(qualified.nonNulls));
    BracketLinkDto link(String from, String to, int slot, [String outcome = "winner"]) => BracketLinkDto((l) => l
      ..fromEventId = from
      ..toEventId = to
      ..outcome = outcome
      ..slot = slot);
    final tree = buildRadialTree(BracketResponseDto((b) => b
      ..sourceUpdatedAt = bracket.sourceUpdatedAt
      ..nodes.addAll([center, for (final n in [shape.opening1, shape.opening2, shape.winners, shape.elimination, shape.decider]) asRound1(n)])
      ..links.addAll([
        link(shape.opening1.eventId, shape.winners.eventId, 0),
        link(shape.opening2.eventId, shape.winners.eventId, 1),
        link(shape.elimination.eventId, shape.decider.eventId, 0),
        // Le décisif reçoit aussi le perdant du match des vainqueurs : le bas du cercle répond au haut.
        link(shape.winners.eventId, shape.decider.eventId, 1, "loser"),
        link(shape.winners.eventId, center.eventId, 0),
        link(shape.decider.eventId, center.eventId, 1),
      ])), loserTargets: {shape.decider.eventId}, loserExpandsSides: true);

    // Ouvertures et vainqueurs dans la moitié du haut, élimination et décisif dans celle du bas.
    assignSectors(tree, {
      shape.winners.eventId: (-math.pi, 0.0),
      shape.decider.eventId: (0.0, math.pi),
    });
    return RadialBracket(
      tree: tree,
      followed: followed,
      center: _QualifiedLabel(participants: qualified),
      centerOpensMatch: false,
      divider: (top: "OUVERTURE", bottom: "ÉLIMINATION"),
    );
  }
}

class _QualifiedLabel extends StatelessWidget {
  const _QualifiedLabel({required this.participants});
  final List<BracketParticipantDto?> participants;

  @override
  Widget build(BuildContext context) {
    // Vert (qualifié) quand la poule est jouée, laiton tant que les deux places ne sont pas prises.
    final done = participants.every((p) => p != null);
    final tint = done ? AppColors.win : AppColors.brass;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, color: tint, size: 20),
        const Text("QUALIFIÉS", style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        for (final p in participants)
          Text(p == null ? "?" : teamCode(p), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p == null ? AppColors.textTertiary : tint)),
      ],
    );
  }
}

/// La case « Qualifiés » à droite de la pyramide : les deux équipes qui sortent de la poule.
class _QualifiedBox extends StatelessWidget {
  const _QualifiedBox({required this.participants});
  final List<BracketParticipantDto?> participants;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip), border: Border.all(color: AppColors.moss)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("QUALIFIÉS", style: TextStyle(fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.moss)),
          for (final p in participants)
            Expanded(
              child: Row(
                children: [
                  BracketTeamLogo(side: (label: p?.name ?? "?", code: p == null ? null : teamCode(p), imageUrl: p?.imageUrl, entityId: p?.entityId, score: null, won: false, lost: false)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p?.name ?? "À déterminer",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: p == null ? 11 : 13, fontWeight: FontWeight.w600, color: p == null ? AppColors.textTertiary : AppColors.textPrimary),
                    ),
                  ),
                  if (p != null) const Icon(Icons.check_rounded, size: 16, color: AppColors.moss),
                ],
              ),
            ),
        ],
      ),
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

const _boxH = 52.0;

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
