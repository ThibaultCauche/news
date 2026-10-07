import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/bracket_match_card.dart";
import "../../widgets/empty_mark.dart";
import "../../widgets/ornate_frame.dart";
import "../follows/follows_provider.dart";
import "../team/team_screen.dart";

/// Classement global d'une compétition (`GET /v1/competitions/:id/ranking`, J23).
final rankingProvider = FutureProvider.autoDispose.family<RankingResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetRanking(id: id);
  return response.data!;
});

/// « Phase suisse », « phase finale »… à partir du nom de l'étape chez le fournisseur et de son format.
String stageLabel(String stage, String? format) {
  final name = stage.toLowerCase();
  if (format == "swiss") return "phase suisse";
  if (name.contains("playoff")) return "phase finale";
  if (name.contains("play-in")) return "play-in";
  if (name.contains("group")) return "phase de groupes";
  return stage;
}

/// Toutes les équipes d'une compétition avec leur statut : championne, en course, éliminée (et à quelle étape),
/// et leur bilan dans leur dernière étape. Le classement dit qui a perdu : avec « sans spoil », il reste masqué
/// jusqu'à un appui sur « Afficher ».
class RankingView extends ConsumerStatefulWidget {
  const RankingView({super.key, required this.competitionId});

  final String competitionId;

  @override
  ConsumerState<RankingView> createState() => _RankingViewState();
}

class _RankingViewState extends ConsumerState<RankingView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final ranking = ref.watch(rankingProvider(widget.competitionId));
    final hidden = (ref.watch(userSettingProvider).value?.spoilerFree ?? true) && !_revealed;
    final followed = (ref.watch(followsProvider).value ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    return AsyncView(
      value: ranking,
      errorMessage: "Impossible de charger le classement.",
      onRetry: () => ref.invalidate(rankingProvider(widget.competitionId)),
      builder: (value) {
        if (value.entries.isEmpty) return const Center(child: EmptyMark("Le classement apparaîtra avec les premiers matchs."));
        if (hidden) return _Hidden(onReveal: () => setState(() => _revealed = true));
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
          children: [
            Text(
              value.finished ? "Classement final" : "Classement en cours",
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            _HowItWorks(swiss: value.entries.any((e) => e.stageFormat == "swiss")),
            const SizedBox(height: AppSpacing.sm),
            FramedCard(
              margin: EdgeInsets.zero,
              child: Column(children: [for (final entry in value.entries) _RankingRow(entry: entry, mine: followed.contains(entry.entityId))]),
            ),
          ],
        );
      },
    );
  }
}

/// Comment lire le classement, en deux phrases (J23) : les statuts, et la règle de la phase suisse quand il y en a une.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.swiss});

  final bool swiss;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary);
    return Text(
      [
        "Chaque équipe (ou joueur) est classée selon l'étape où elle en est, puis selon son bilan (victoires – défaites) dans cette étape.",
        if (swiss) "En phase suisse, 3 victoires qualifient et 3 défaites éliminent.",
      ].join(" "),
      style: style,
    );
  }
}

class _Hidden extends StatelessWidget {
  const _Hidden({required this.onReveal});

  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_off_rounded, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          const Text("Classement masqué (sans spoil).", style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onReveal, child: const Text("Afficher")),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry, required this.mine});

  final RankingEntryDto entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final stage = stageLabel(entry.stage, entry.stageFormat);
    final (label, color) = switch (entry.status) {
      RankingEntryDtoStatusEnum.champion => ("Championne", AppColors.win),
      RankingEntryDtoStatusEnum.inRace when entry.qualified => ("Qualifiée · $stage", AppColors.win),
      RankingEntryDtoStatusEnum.inRace => ("En course · $stage", AppColors.brass),
      _ => ("Éliminée · $stage", AppColors.textTertiary),
    };
    final side = (
      label: entry.name,
      code: entry.shortName ?? entry.name.substring(0, entry.name.length < 3 ? entry.name.length : 3).toUpperCase(),
      imageUrl: entry.imageUrl,
      entityId: entry.entityId,
      score: null,
      won: false,
      lost: false,
    );
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(entityId: entry.entityId, breadcrumb: "Classement"))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text("${entry.rank}", style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
            BracketTeamLogo(side: side),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: mine ? AppColors.gold : AppColors.textPrimary)),
                  Text(label, style: TextStyle(color: color, fontSize: AppTypography.caption, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text("${entry.wins}-${entry.losses}", style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
