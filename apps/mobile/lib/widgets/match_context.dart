import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";
import "../theme/tokens.dart";
import "game_logo.dart";

/// « Champions 2026 · Groupe C » : le tournoi puis l'étape (J22, #A1). Sans tournoi parent connu,
/// le nom de la compétition seul. L'étape est en français quand l'éditeur la donne en anglais.
String matchContextLabel(CompetitionRefDto competition) {
  final stage = competition.name.replaceFirst(RegExp(r"^Group "), "Groupe ");
  final tournament = competition.tournamentName;
  if (tournament == null || tournament == competition.name) return stage;
  return "$tournament · $stage";
}

/// Ligne de contexte d'une carte ou d'un en-tête de groupe : logo du jeu (s'il est connu) puis
/// `matchContextLabel`.
class MatchContextLine extends StatelessWidget {
  const MatchContextLine({super.key, required this.competition, this.suffix, this.style, this.uppercase = false});

  final CompetitionRefDto competition;

  /// Capitales (en-têtes de groupe), comme les libellés de section du reste de l'appli.
  final bool uppercase;

  /// Fin de ligne (ex. « BO3 »), séparée par un point médian.
  final String? suffix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final game = competition.game;
    final joined = [matchContextLabel(competition), ?suffix].join(" · ");
    final label = uppercase ? joined.toUpperCase() : joined;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (game != null) ...[GameLogo(slug: game, size: 16), const SizedBox(width: 6)],
        Flexible(child: Text(label, style: style ?? Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// En-tête d'un groupe de matchs d'une même compétition (J22, #A3), collant dans l'Agenda.
class CompetitionGroupHeader extends StatelessWidget {
  const CompetitionGroupHeader({super.key, required this.competition});

  final CompetitionRefDto competition;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: MatchContextLine(competition: competition, uppercase: true, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.brass)),
    );
  }
}

/// Délégué d'en-tête collant, hauteur fixe.
class CompetitionHeaderDelegate extends SliverPersistentHeaderDelegate {
  CompetitionHeaderDelegate(this.competition);

  final CompetitionRefDto competition;

  @override
  double get minExtent => CompetitionGroupHeader.height;
  @override
  double get maxExtent => CompetitionGroupHeader.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => CompetitionGroupHeader(competition: competition);

  @override
  bool shouldRebuild(CompetitionHeaderDelegate oldDelegate) => oldDelegate.competition != competition;
}

/// Regroupe des matchs par compétition en gardant l'ordre du premier match de chaque groupe.
List<(CompetitionRefDto, List<EventSummaryDto>)> groupByCompetition(Iterable<EventSummaryDto> events) {
  final groups = <String, (CompetitionRefDto, List<EventSummaryDto>)>{};
  for (final event in events) {
    groups.putIfAbsent(matchContextLabel(event.competition), () => (event.competition, [])).$2.add(event);
  }
  return groups.values.toList();
}
