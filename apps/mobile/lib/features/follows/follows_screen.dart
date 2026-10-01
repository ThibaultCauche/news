import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../widgets/page_title.dart";
import "../../core/navigation.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../competitions/competitions_data.dart";
import "../competitions/game_screen.dart";
import "../competitions/league_screen.dart";
import "../next_match/next_match_screen.dart";
import "../team/team_screen.dart";
import "follows_provider.dart";

/// Écran Suivis (docs/04 J4) : une carte par suivi avec son état en une ligne (docs/02
/// §"Architecture de l'accueil"). Depuis le J11 ce n'est plus un onglet mais un écran ouvert
/// depuis « Tes suivis » de l'Accueil, du Profil et des Réglages.
class FollowsScreen extends ConsumerWidget {
  const FollowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(followsProvider.future),
          child: switch (follows) {
            // Pendant un rechargement automatique, on garde l'ancien contenu (pas de spinner).
            _ when follows.hasValue => _FollowsBody(follows: follows.value!),
            AsyncError() => const Center(child: Text("Impossible de charger tes suivis.", style: TextStyle(color: AppColors.textSecondary))),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _FollowsBody extends ConsumerWidget {
  const _FollowsBody({required List<FollowStateDto> follows}) : allFollows = follows;

  final List<FollowStateDto> allFollows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Une sourdine (« sauf cette compétition », J10) n'est pas un suivi : pas de carte.
    final follows = allFollows.where((f) => !f.muted).toList();
    if (follows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const PageTitle("Suivis"),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            "Tu ne suis rien pour l'instant. Suis une compétition ou une équipe pour retrouver ses matchs ici.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                ref.read(tabIndexProvider.notifier).select(competitionsTabIndex);
              },
              child: const Text("Explorer les compétitions"),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: follows.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i == 0) return const PageTitle("Suivis");
        final follow = follows[i - 1];
        return FollowCard(follow: follow, targetType: followTargetTypeFromWire(follow.targetType));
      },
    );
  }
}

/// Carte d'un suivi : nom (mène à sa page), état, prochain match.
class FollowCard extends ConsumerWidget {
  const FollowCard({super.key, required this.follow, required this.targetType});

  final FollowStateDto follow;
  final FollowTargetType targetType;

  String get _initials {
    final trimmed = follow.name.trim();
    return (trimmed.length <= 3 ? trimmed : trimmed.substring(0, 3)).toUpperCase();
  }

  // Le nom mène à la page de ce qu'on suit (compétition, fiche équipe, match) : le
  // désabonnement se fait depuis cette page (docs/04 J10). Une catégorie n'a pas de page.
  VoidCallback? _onOpen(BuildContext context, WidgetRef ref) => switch (targetType) {
    FollowTargetType.competition => () async {
      // Une ligue racine (VCT…) a sa propre page ; le reste (série, étape) la page compétition.
      // Catalogue chargé au tap (il ne l'est pas forcément ici) ; en cas d'échec, page compétition.
      final catalog = await ref.read(catalogProvider.future).then<CatalogDto?>((c) => c).catchError((_) => null);
      if (!context.mounted) return;
      final found = findLeague(catalog, follow.targetId);
      if (found != null) {
        openLeaguePage(context, league: found.league, game: found.game);
      } else {
        openCompetitionPage(context, id: follow.targetId, name: follow.name);
      }
    },
    FollowTargetType.competitionFamily => () async {
      // Une famille appartient à une ligue : on ouvre sa page, où se gère le suivi.
      final catalog = await ref.read(catalogProvider.future).then<CatalogDto?>((c) => c).catchError((_) => null);
      if (!context.mounted) return;
      final found = findLeagueOfFamily(catalog, follow.targetId);
      if (found != null) openLeaguePage(context, league: found.league, game: found.game);
    },
    FollowTargetType.entity => () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(entityId: follow.targetId, breadcrumb: "Suivis"))),
    FollowTargetType.event => () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: follow.targetId))),
    FollowTargetType.category => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = follow.currentEvent;
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _onOpen(context, ref),
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, 0),
                child: Row(
                  children: [
                    if (targetType == FollowTargetType.entity) ...[
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surface,
                        foregroundImage: follow.imageUrl != null ? NetworkImage(follow.imageUrl!) : null,
                        child: Text(_initials, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(follow.name, style: Theme.of(context).textTheme.titleLarge),
                          if (targetType == FollowTargetType.competitionFamily)
                            const Text("Toutes les éditions", style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                          if (follow.status != null) _StatusPill(status: follow.status!),
                        ],
                      ),
                    ),
                    if (_onOpen(context, ref) != null) const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            if (event != null)
              EventCard(
                event: event,
                scoresHidden: scoresHidden,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
              )
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
                child: Text("Rien de prévu pour l'instant.", style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Encore en course" / "Éliminée" (docs/04 J8) : vert réservé
/// victoire/qualifié (règle 12 de `CLAUDE.md`), gris neutre sinon — jamais
/// rouge, réservé au direct.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final FollowStateDtoStatusEnum status;

  @override
  Widget build(BuildContext context) {
    final qualified = status == FollowStateDtoStatusEnum.qualified;
    final color = qualified ? AppColors.win : AppColors.loss;
    return Text(qualified ? "Encore en course" : "Éliminée", style: TextStyle(color: color, fontSize: AppTypography.caption, fontWeight: FontWeight.w600));
  }
}
