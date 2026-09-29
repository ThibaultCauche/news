import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
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

/// Écran Suivis, remplace le placeholder du J3 (docs/04 J4) : une carte par
/// suivi avec son état en une ligne (docs/02 §"Architecture de l'accueil").
class FollowsScreen extends ConsumerWidget {
  const FollowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(followsProvider.future),
        child: switch (follows) {
          AsyncData(:final value) => _FollowsBody(follows: value),
          AsyncError() when follows.hasValue => _FollowsBody(follows: follows.value!),
          AsyncError() => const Center(child: Text("Impossible de charger tes suivis.", style: TextStyle(color: AppColors.textSecondary))),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _FollowsBody extends ConsumerWidget {
  const _FollowsBody({required this.follows});

  final List<FollowStateDto> follows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (follows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text("Suivis", style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            "Tu ne suis rien pour l'instant. Suis une compétition ou une équipe pour retrouver ses matchs ici.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => ref.read(tabIndexProvider.notifier).select(competitionsTabIndex),
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
        if (i == 0) return Text("Suivis", style: Theme.of(context).textTheme.headlineLarge);
        final follow = follows[i - 1];
        return _FollowCard(follow: follow, targetType: FollowTargetType.values.byName(follow.targetType));
      },
    );
  }
}

class _FollowCard extends ConsumerWidget {
  const _FollowCard({required this.follow, required this.targetType});

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
