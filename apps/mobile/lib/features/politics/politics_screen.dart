import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../next_match/next_match_screen.dart";
import "election_widgets.dart";
import "law_screen.dart";
import "politics_model.dart";
import "vote_widgets.dart" show SourceNote;

final politicsOverviewProvider = FutureProvider.autoDispose<PoliticsOverviewDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getPoliticsApi().politicsControllerGet();
  return response.data!;
});

void openLaw(BuildContext context, String competitionId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LawScreen(competitionId: competitionId)));

/// Page « Politique » (J29) : ce que l'Assemblée nationale vient de voter, les textes en cours d'examen et les dernières
/// lois promulguées. Que des faits officiels, avec leur source (docs/01c, règle 9 de CLAUDE.md).
class PoliticsScreen extends ConsumerWidget {
  const PoliticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(politicsOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary)),
        actions: [IconButton(tooltip: "Notre règle de neutralité", icon: const Icon(Icons.balance_rounded), onPressed: () => showNeutralitySheet(context))],
      ),
      body: AsyncView(
        value: overview,
        errorMessage: "Impossible de charger la politique.",
        onRetry: () => ref.invalidate(politicsOverviewProvider),
        builder: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final PoliticsOverviewDto data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        const PageTitle("Politique"),
        const SizedBox(height: AppSpacing.sm),
        const Text("Assemblée nationale · 17ᵉ législature", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.bodyLarge)),
        const SizedBox(height: AppSpacing.lg),
        if (data.elections.isNotEmpty) ...[
          const SectionLabel("ÉLECTIONS"),
          const SizedBox(height: AppSpacing.sm),
          for (final election in data.elections.take(3)) ...[ElectionTile(election: election), const SizedBox(height: AppSpacing.sm)],
          const SizedBox(height: AppSpacing.sm),
        ],
        if (data.votes.isNotEmpty) ...[
          const SectionLabel("DERNIERS VOTES"),
          const SizedBox(height: AppSpacing.sm),
          for (final vote in data.votes.take(5)) ...[VoteTile(vote: vote), const SizedBox(height: AppSpacing.sm)],
          const SizedBox(height: AppSpacing.sm),
        ],
        if (data.inProgress.isNotEmpty) ...[
          const SectionLabel("TEXTES EN COURS"),
          const SizedBox(height: AppSpacing.sm),
          for (final law in data.inProgress) ...[LawTile(law: law), const SizedBox(height: AppSpacing.sm)],
          const SizedBox(height: AppSpacing.sm),
        ],
        if (data.promulgated.isNotEmpty) ...[
          const SectionLabel("DERNIÈRES LOIS PROMULGUÉES"),
          const SizedBox(height: AppSpacing.sm),
          for (final law in data.promulgated) ...[LawTile(law: law), const SizedBox(height: AppSpacing.sm)],
        ],
        if (data.votes.isEmpty && data.inProgress.isEmpty && data.promulgated.isEmpty && data.elections.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xl), child: Center(child: Text("Rien à suivre pour l'instant.", style: TextStyle(color: AppColors.textSecondary)))),
        const SizedBox(height: AppSpacing.md),
        const SourceNote(),
      ],
    );
  }
}

/// Un scrutin dans la page Politique : sa date, et « ce soir » ou le compte à rebours du blocage de 20 h.
class ElectionTile extends StatelessWidget {
  const ElectionTile({super.key, required this.election});

  final ElectionCardDto election;

  @override
  Widget build(BuildContext context) {
    final tonight = election.phase == ElectionCardDtoPhaseEnum.tonight;
    final upcoming = election.phase == ElectionCardDtoPhaseEnum.upcoming;
    final caption = tonight
        ? (election.embargoed ? "Ce soir · résultats à 20\u00a0h" : "Ce soir · résultats en direct")
        : upcoming
            ? "${electionDateLabel(election.date)} · résultats à 20\u00a0h"
            : electionDateLabel(election.date);
    return Semantics(
      button: true,
      label: "${election.name}. $caption",
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ElectionScreen(competitionId: election.competitionId))),
          child: SectionCard(
            highlight: tonight,
            child: Row(
              children: [
                Icon(upcoming || (tonight && election.embargoed) ? Icons.lock_outline_rounded : Icons.how_to_vote_outlined, color: AppColors.brass),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(election.name, style: AppTextStyles.bodyLargeStrong),
                      const SizedBox(height: 2),
                      Text(caption, style: TextStyle(color: tonight ? AppColors.live : AppColors.textSecondary, fontSize: AppTypography.caption)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un texte de loi dans une liste : son type, son titre officiel, où il en est.
class LawTile extends StatelessWidget {
  const LawTile({super.key, required this.law});

  final LawCardDto law;

  @override
  Widget build(BuildContext context) {
    final promulgated = law.status == LawCardDtoStatusEnum.promulgated;
    final date = lawDayLabel(law.lastDate);
    return Semantics(
      button: true,
      label: "${law.lawType}. ${law.name}. ${law.stepLabel ?? ""}. $date",
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: () => openLaw(context, law.id),
          child: SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(law.lawType, style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.label, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(law.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyLargeStrong),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(promulgated ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded, size: 14, color: promulgated ? AppColors.win : AppColors.live),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [?law.stepLabel, if (date.isNotEmpty) date].join(" · "),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un vote dans une liste : le texte voté, le résultat en une phrase et une barre pour / contre / abstention.
class VoteTile extends StatelessWidget {
  const VoteTile({super.key, required this.vote});

  final VoteCardDto vote;

  @override
  Widget build(BuildContext context) {
    final pour = vote.outcome.pour.toInt(), contre = vote.outcome.contre.toInt(), abst = vote.outcome.abst.toInt();
    return Semantics(
      button: true,
      label: "${vote.lawName ?? vote.name}. ${vote.outcome.sentence}. ${lawDayLabel(vote.date)}",
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: vote.eventId))),
          child: SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lawDayLabel(vote.date), style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.label, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(vote.lawName ?? vote.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyLargeStrong),
                const SizedBox(height: AppSpacing.sm),
                OutcomeBar(pour: pour, contre: contre, abst: abst),
                const SizedBox(height: 6),
                Text(vote.outcome.sentence, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre pour (blanc), contre (laiton), abstention (gris) : les parts d'un vote.
class OutcomeBar extends StatelessWidget {
  const OutcomeBar({super.key, required this.pour, required this.contre, required this.abst});

  final int pour;
  final int contre;
  final int abst;

  @override
  Widget build(BuildContext context) {
    final empty = pour + contre + abst == 0;
    return SizedBox(
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            if (pour > 0) Expanded(flex: pour, child: const ColoredBox(color: AppColors.textPrimary, child: SizedBox.expand())),
            if (contre > 0) Expanded(flex: contre, child: const ColoredBox(color: AppColors.brass, child: SizedBox.expand())),
            if (abst > 0) Expanded(flex: abst, child: const ColoredBox(color: AppColors.textSecondary, child: SizedBox.expand())),
            if (empty) const Expanded(child: ColoredBox(color: AppColors.surfaceBorder, child: SizedBox.expand())),
          ],
        ),
      ),
    );
  }
}

/// La charte de neutralité, en clair (docs/01c) : ce que l'appli fait et ne fera jamais en politique.
void showNeutralitySheet(BuildContext context) {
  const rules = [
    ("Que des faits officiels", "Chaque vote et chaque étape d'un texte viennent de l'open data de l'Assemblée nationale, avec le lien vers la source."),
    ("Les noms officiels", "Les groupes portent le nom que l'Assemblée leur donne, jamais une étiquette de notre part."),
    ("Aucun ordre politique", "Les groupes sont rangés par ordre alphabétique, pas de gauche à droite ni par taille."),
    ("Des phrases à trous", "« Adopté : 312 pour, 198 contre » : des gabarits fixes remplis avec les chiffres officiels, pas de texte libre."),
    ("Ni pronostic ni commentaire", "Pas de prévision électorale, pas d'avis sur le fond d'un texte. Le code est ouvert : chacun peut le vérifier."),
  ];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Notre règle de neutralité", style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            for (final (title, body) in rules) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_rounded, size: 18, color: AppColors.brass)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTextStyles.bodyLargeStrong),
                        const SizedBox(height: 2),
                        Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    ),
  );
}
