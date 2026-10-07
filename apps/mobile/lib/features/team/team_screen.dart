import "package:flutter/material.dart";
import "../learn/learn_screen.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../theme/app_theme.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/games.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/event_card.dart";
import "../../widgets/follow_button.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../follows/follows_provider.dart";
import "../discussion/share_sheet.dart";
import "../forum/forum_entry.dart";
import "../next_match/next_match_screen.dart";

final entityProvider = FutureProvider.autoDispose.family<EntityResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getEntitiesApi().entitiesControllerGetById(id: id);
  return response.data!;
});

/// Fiche équipe (écran 10, `docs/02`). Pas de "Transferts et effectif" : aucune
/// source de roster branchée (`docs/04` J6, voir `EntityResponseDto`).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key, required this.entityId, this.breadcrumb});

  final String entityId;
  final String? breadcrumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = ref.watch(entityProvider(entityId));
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: Text(breadcrumb ?? "", overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        actions: [const LearnHelpButton(articleId: "fiche-equipe", game: "app"), ShareButton(kind: ShareDtoKindEnum.team, refId: entityId)],
      ),
      body: switch (entity) {
        _ when entity.hasValue => _TeamBody(entity: entity.value!, scoresHidden: scoresHidden),
        AsyncError() => ErrorState(message: "Impossible de charger cette équipe.", onRetry: () => ref.invalidate(entityProvider(entityId))),
        _ => const SkeletonCards(count: 3, height: 120),
      },
    );
  }
}

class _TeamBody extends ConsumerWidget {
  const _TeamBody({required this.entity, required this.scoresHidden});

  final EntityResponseDto entity;
  final bool scoresHidden;

  String get _initials {
    final raw = entity.shortName ?? entity.name;
    return (raw.length <= 3 ? raw : raw.substring(0, 3)).toUpperCase();
  }

  String get _nextMatchLabel {
    final start = entity.nextEvent?.startsAt.toDateTime?.toLocal();
    if (start == null) return "—";
    final remaining = start.difference(DateTime.now());
    if (remaining.isNegative) return "En cours";
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return h > 0 ? "$h h $m" : "$m min";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.entity, entity.id);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.surface, child: Text(_initials, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entity.name, style: AppTextStyles.pageTitle),
                  if (entity.region != null) Text(entity.region!, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            FollowButton(
              following: following,
              onPressed: () => following
                  ? ref.read(followsControllerProvider).unfollow(FollowTargetType.entity, entity.id)
                  : ref.read(followsControllerProvider).follow(FollowTargetType.entity, entity.id),
            ),
          ],
        ),
        if (entity.organization != null) ...[
          const SizedBox(height: AppSpacing.md),
          OrganizationFollowTile(organization: entity.organization!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: _StatTile(label: "Bilan", value: "${entity.wins}–${entity.losses}")),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(child: _StatTile(label: "Victoires d'affilée", value: "${entity.winStreak}")),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(child: _StatTile(label: "Prochain match", value: _nextMatchLabel)),
          ],
        ),
        if (entity.lastEvent != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel("DERNIER MATCH"),
          const SizedBox(height: AppSpacing.sm),
          // `EventCard` porte désormais sa propre bulle (même fond/bordure
          // qu'un `SectionCard`) : plus besoin de l'y envelopper.
          EventCard(
            event: entity.lastEvent!,
            scoresHidden: scoresHidden,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: entity.lastEvent!.id))),
          ),
        ],
        if (entity.nextEvent != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel("PROCHAIN MATCH"),
          const SizedBox(height: AppSpacing.sm),
          EventCard(
            event: entity.nextEvent!,
            scoresHidden: scoresHidden,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: entity.nextEvent!.id))),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ForumEntryCard(kind: "entity", targetId: entity.id),
      ],
    );
  }
}

/// « Suivre toute G2 » (J23, #A4) : la structure regroupe les équipes de même nom dans plusieurs jeux. Suivre la
/// structure suit chacune de ses équipes, et celles qui la rejoindront.
class OrganizationFollowTile extends ConsumerWidget {
  const OrganizationFollowTile({super.key, required this.organization});

  final EntityOrganizationDto organization;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.organization, organization.id);
    final games = organization.games.map(gameLabel).join(", ");
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Toute ${organization.name}", style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  "${organization.teamCount} équipes${games.isEmpty ? "" : " · $games"}",
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FollowButton(
            following: following,
            onPressed: () => runOrShowError(
              context,
              () => following
                  ? ref.read(followsControllerProvider).unfollow(FollowTargetType.organization, organization.id)
                  : ref.read(followsControllerProvider).follow(FollowTargetType.organization, organization.id, name: organization.name),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
        ],
      ),
    );
  }
}
