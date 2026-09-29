import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/iterable_x.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../../widgets/live_dot.dart";
import "../follows/follows_provider.dart";
import "../next_match/next_match_screen.dart";
import "../settings/settings_screen.dart";

final homeProvider = FutureProvider.autoDispose<HomeResponseDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getHomeApi().homeControllerGetHome();
  return response.data!;
});

/// Écran 17 (`docs/02`). Sans abonnements (comptes = J4), on affiche ce que
/// `/v1/home` fournit déjà : en direct, grands rendez-vous, à venir — pas
/// encore de "Tes suivis" personnalisé.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(homeProvider.future),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _HomeHeader()),
            switch (home) {
              AsyncData(:final value) => _HomeBody(home: value, scoresHidden: scoresHidden),
              AsyncError() when home.hasValue => _HomeBody(home: home.value!, scoresHidden: scoresHidden),
              AsyncError() => const SliverFillRemaining(child: Center(child: Text("Impossible de charger l'accueil."))),
              _ => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            },
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final date = DateFormat("EEEE d MMMM", "fr_FR").format(DateTime.now());
    final capitalized = date[0].toUpperCase() + date.substring(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(capitalized, style: const TextStyle(color: AppColors.textSecondary)),
                Text("Aujourd'hui", style: Theme.of(context).textTheme.headlineLarge),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _comingSoon(context, "Explorer"),
            icon: const Icon(Icons.search_rounded),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: const CircleAvatar(
              backgroundColor: AppColors.surface,
              child: Text("T"),
            ),
          ),
        ],
      ),
    );
  }

  static void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label bientôt disponible")));
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.home, required this.scoresHidden});

  final HomeResponseDto home;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    final live = home.liveNow.toList();
    final upcoming = home.upcoming.toList();
    final highlights = home.highlights.toList();
    // "Maintenant pour toi" (docs/02, écran 17) : d'abord ce qui est suivi et
    // en direct, sinon le premier direct générique ; si rien n'est en direct,
    // le bandeau retombe sur le prochain match à venir ("à suivre") plutôt que
    // de disparaître.
    final liveEvent = home.nowForYou?.status == "live" ? home.nowForYou : live.firstOrNull;
    final upNextEvent = liveEvent == null ? (home.nowForYou ?? upcoming.firstOrNull) : null;
    final follows = home.follows.where((f) => f.currentEvent != null).toList();

    return SliverList(
      delegate: SliverChildListDelegate([
        if (liveEvent != null) _MatchBanner(event: liveEvent, next: upcoming.firstOrNull, isLive: true),
        if (liveEvent == null && upNextEvent != null) _MatchBanner(event: upNextEvent, isLive: false),
        if (follows.isNotEmpty) _FollowsSection(follows: follows, scoresHidden: scoresHidden),
        if (highlights.isNotEmpty) _HighlightsSection(events: highlights.take(5).toList()),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

/// "Maintenant pour toi" (docs/02, écran 17) : en direct (rouge, `docs/02`
/// règle des couleurs) si quelque chose l'est, sinon le prochain match à venir
/// ("à suivre", ton neutre — ce n'est pas forcément un suivi).
class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.event, required this.isLive, this.next});

  final EventSummaryDto event;
  final bool isLive;
  final EventSummaryDto? next;

  String _scheduleLabel(DateTime start) {
    final local = start.toLocal();
    final now = DateTime.now();
    final days = DateTime(local.year, local.month, local.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final day = switch (days) {
      0 => "Aujourd'hui",
      1 => "Demain",
      _ => DateFormat("d MMMM", "fr_FR").format(local),
    };
    return "$day à ${DateFormat.Hm("fr_FR").format(local)}";
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = isLive ? AppColors.live : AppColors.textSecondary;
    final title = isLive && event.participants.length == 2
        ? "${event.participants[0].name} ${event.participants[0].score ?? 0}-${event.participants[1].score ?? 0} ${event.participants[1].name}"
        : event.participants.length == 2
        ? "${event.participants[0].name} – ${event.participants[1].name}"
        : event.name;
    final start = event.startsAt.toDateTime;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isLive ? AppColors.live.withValues(alpha: 0.12) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: isLive ? AppColors.live.withValues(alpha: 0.4) : AppColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isLive) ...[const LiveDot(), const SizedBox(width: AppSpacing.xs)],
                  Text(isLive ? "EN DIRECT" : "À SUIVRE", style: textTheme.labelSmall?.copyWith(color: accent)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(event.competition.name, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: textTheme.titleLarge),
              if (!isLive && start != null) ...[
                const SizedBox(height: 2),
                Text(_scheduleLabel(start), style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
              if (isLive && next != null) ...[
                const Divider(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Ensuite : ${next!.participants.map((p) => p.shortName ?? p.name).join(" – ")}",
                        style: textTheme.bodySmall?.copyWith(color: AppColors.gold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tes suivis" (docs/02, écran 17) : une carte par suivi qui a un match en
/// cours ou à venir. Ceux sans rien de prévu restent réservés à l'écran Suivis.
class _FollowsSection extends StatelessWidget {
  const _FollowsSection({required this.follows, required this.scoresHidden});

  final List<FollowStateDto> follows;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text("Tes suivis", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.gold)),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Chaque `EventCard` porte désormais sa propre bulle : plus de `Card`
        // englobante qui les aurait doublement encadrées.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              for (final follow in follows)
                EventCard(
                  event: follow.currentEvent!,
                  scoresHidden: scoresHidden,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: follow.currentEvent!.id))),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _HighlightsSection extends StatelessWidget {
  const _HighlightsSection({required this.events});

  final List<EventSummaryDto> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text("Les grands rendez-vous", style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => _HighlightCard(event: events[i]),
          ),
        ),
      ],
    );
  }
}

class _HighlightCard extends ConsumerWidget {
  const _HighlightCard({required this.event});

  final EventSummaryDto event;

  String get _title =>
      event.participants.length == 2 ? "${event.participants[0].name} – ${event.participants[1].name}" : event.name;

  String get _timing {
    final start = event.startsAt.toDateTime;
    if (start == null) return event.competition.name;
    final days = start.toLocal().difference(DateTime.now()).inDays;
    return switch (days) {
      <= 0 => "Aujourd'hui",
      1 => "Demain",
      _ => "Dans $days jours",
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradient = AppGradients.highlights[event.id.hashCode.abs() % AppGradients.highlights.length];
    final textTheme = Theme.of(context).textTheme;
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.event, event.id);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id)),
      ),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.sports_esports_rounded, color: AppColors.textSecondary),
            Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge?.copyWith(fontSize: 17)),
            Row(
              children: [
                Expanded(
                  child: Text(_timing, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: AppSpacing.xs),
                _FollowPill(
                  following: following,
                  onTap: () => following
                      ? ref.read(followsControllerProvider).unfollow(FollowTargetType.event, event.id)
                      : ref.read(followsControllerProvider).follow(FollowTargetType.event, event.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton "Suivre" partout (docs/04 J4) : `POST`/`DELETE /v1/subscriptions`
/// via `followsControllerProvider`, l'état vient de `followsProvider`.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: following ? Colors.transparent : AppColors.textPrimary,
          border: following ? Border.all(color: AppColors.textTertiary) : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          following ? "Suivi ✓" : "Suivre",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: following ? AppColors.textSecondary : AppColors.background,
          ),
        ),
      ),
    );
  }
}

