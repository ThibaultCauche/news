import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../next_match/next_match_screen.dart";
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
            "Tu ne suis rien pour l'instant. Le bouton « Suivre » est disponible partout dans l'appli.",
            style: TextStyle(color: AppColors.textSecondary),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, 0),
              child: Row(
                children: [
                  Expanded(child: Text(follow.name, style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textTertiary),
                    tooltip: "Ne plus suivre",
                    onPressed: () => ref.read(followsControllerProvider).unfollow(targetType, follow.targetId),
                  ),
                ],
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
