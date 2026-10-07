import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/bracket_match_card.dart";
import "../follows/follows_provider.dart";
import "bracket_model.dart";
import "stage_pick.dart";
import "swiss_model.dart";

/// Phase suisse (J23) : une colonne par ronde, les matchs rangés par bilan (« 2-1 »), puis les équipes qualifiées
/// et éliminées. Défile à l'horizontale, comme la pyramide d'une poule.
class SwissView extends ConsumerWidget {
  const SwissView({super.key, required this.bracket, required this.competitionId});

  final BracketResponseDto bracket;

  /// L'étape (« Group Stage ») : cible du pronostic.
  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = buildSwissLayout(bracket);
    final byId = {for (final n in bracket.nodes) n.eventId: n};
    final followed = (ref.watch(followsProvider).value ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    final next = nextMatchId(bracket, followed);
    if (layout.rounds.isEmpty) return const Text("Pas encore de ronde.", style: TextStyle(color: AppColors.textSecondary));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StagePickCard(competitionId: competitionId),
        SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final round in layout.rounds)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: SizedBox(
                width: bracketCardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("RONDE ${round.number}", style: AppTextStyles.sectionTitle.copyWith(fontSize: 13, color: AppColors.brass)),
                    for (final group in round.groups) ...[
                      const SizedBox(height: AppSpacing.sm),
                      // Pas de bilan tant que les équipes de la ronde ne sont pas connues.
                      if (group.record != "?") ...[
                        Text(
                          "Bilan ${group.record}",
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                      ],
                      for (final match in group.matches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: BracketMatchCard(
                            node: match,
                            sides: matchSides(match, const [], byId),
                            followed: followed,
                            emphasis: match.status == "live" ? CardEmphasis.live : (match.eventId == next ? CardEmphasis.next : CardEmphasis.none),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          _TeamsColumn(title: "QUALIFIÉES", teams: layout.qualified, color: AppColors.win, followed: followed),
          const SizedBox(width: AppSpacing.md),
          _TeamsColumn(title: "ÉLIMINÉES", teams: layout.eliminated, color: AppColors.textTertiary, followed: followed),
        ],
      ),
        ),
      ],
    );
  }
}

class _TeamsColumn extends StatelessWidget {
  const _TeamsColumn({required this.title, required this.teams, required this.color, required this.followed});

  final String title;
  final List<BracketParticipantDto> teams;
  final Color color;
  final Set<String> followed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$title (${teams.length})", style: AppTextStyles.sectionTitle.copyWith(fontSize: 13, color: color)),
          const SizedBox(height: AppSpacing.sm),
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  BracketTeamLogo(
                    side: (label: team.name, code: teamCode(team), imageUrl: team.imageUrl, entityId: team.entityId, score: null, won: false, lost: false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      teamCode(team),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: followed.contains(team.entityId) ? AppColors.gold : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
