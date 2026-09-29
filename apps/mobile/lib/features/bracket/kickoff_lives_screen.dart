import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/tokens.dart";
import "../../widgets/competition_follow_button.dart";
import "bracket_provider.dart";

const _maxLives = 3;

/// Écran 14 : triple élimination du Kickoff expliquée par les vies plutôt que
/// par un arbre (`docs/02` — « Réponses de design aux formats difficiles »).
/// Ne dépend que de `standings` (`livesLeft`), déjà servi par
/// `/v1/competitions/:id` (J2) : pas de nouvel appel réseau.
class KickoffLivesScreen extends ConsumerWidget {
  const KickoffLivesScreen({super.key, required this.competitionId, required this.title, required this.subtitle});

  final String competitionId;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(competitionId));
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: const Text("Valorant", style: TextStyle(color: AppColors.textSecondary)),
        ),
        actions: [CompetitionFollowButton(competitionId: competitionId, name: title)],
      ),
      body: switch (detail) {
        AsyncData(:final value) => _LivesBody(title: title, subtitle: subtitle, standings: value.standings.toList()),
        AsyncError() => const Center(child: Text("Impossible de charger ce tournoi.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _LivesBody extends StatelessWidget {
  const _LivesBody({required this.title, required this.subtitle, required this.standings});
  final String title;
  final String subtitle;
  final List<CompetitionStandingDto> standings;

  @override
  Widget build(BuildContext context) {
    final byLives = <int, List<CompetitionStandingDto>>{};
    for (final s in standings) {
      byLives.putIfAbsent((s.livesLeft ?? 0).toInt(), () => []).add(s);
    }
    final tiers = byLives.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.card)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Chaque équipe a 3 vies", style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: AppSpacing.xs),
              Text(
                "Une défaite = une vie en moins et on descend d'un tableau. Le vainqueur de chaque tableau gagne un ticket pour les Masters.",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final lives in tiers) _LivesTier(lives: lives, standings: byLives[lives]!),
      ],
    );
  }
}

class _LivesTier extends StatelessWidget {
  const _LivesTier({required this.lives, required this.standings});
  final int lives;
  final List<CompetitionStandingDto> standings;

  String get _label => switch (lives) {
        _maxLives => "Tableau principal · $lives vies",
        0 => "Éliminées",
        _ => "2ᵉ chance · $lives vie${lives > 1 ? "s" : ""}",
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
              child: Text(_label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            ),
            for (final s in (standings..sort((a, b) => (a.rank ?? 99).compareTo(b.rank ?? 99)))) _TeamLivesRow(standing: s),
          ],
        ),
      ),
    );
  }
}

class _TeamLivesRow extends StatelessWidget {
  const _TeamLivesRow({required this.standing});
  final CompetitionStandingDto standing;

  @override
  Widget build(BuildContext context) {
    final lives = standing.livesLeft ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(standing.entityName, overflow: TextOverflow.ellipsis)),
          if (standing.qualified == true)
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(color: AppColors.win.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadii.pill)),
              child: const Text("Qualifié", style: TextStyle(color: AppColors.win, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          Row(
            children: [
              for (var i = 0; i < _maxLives; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Icon(Icons.circle, size: 8, color: i < lives ? AppColors.textPrimary : AppColors.surfaceBorder),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
