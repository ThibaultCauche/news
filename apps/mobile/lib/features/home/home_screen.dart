import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/date_x.dart";
import "../../core/iterable_x.dart";
import "../../theme/tokens.dart";
import "../../widgets/live_dot.dart";
import "../next_match/next_match_screen.dart";

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
    return RefreshIndicator(
      onRefresh: () => ref.refresh(homeProvider.future),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _HomeHeader()),
          switch (home) {
            AsyncData(:final value) => _HomeBody(home: value),
            AsyncError() when home.hasValue => _HomeBody(home: home.value!),
            AsyncError() => const SliverFillRemaining(child: Center(child: Text("Impossible de charger l'accueil."))),
            _ => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
          },
        ],
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
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
            onTap: () => _comingSoon(context, "Réglages"),
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
  const _HomeBody({required this.home});

  final HomeResponseDto home;

  @override
  Widget build(BuildContext context) {
    final live = home.liveNow.toList();
    final upcoming = home.upcoming.toList();
    final highlights = home.highlights.toList();

    return SliverList(
      delegate: SliverChildListDelegate([
        if (live.isNotEmpty) _LiveBanner(event: live.first, next: upcoming.firstOrNull),
        if (highlights.isNotEmpty) _HighlightsSection(events: highlights.take(5).toList()),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.event, this.next});

  final EventSummaryDto event;
  final EventSummaryDto? next;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = event.participants.length == 2
        ? "${event.participants[0].name} ${event.participants[0].score ?? 0}-${event.participants[1].score ?? 0} ${event.participants[1].name}"
        : event.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.live.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.live.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LiveDot(),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    "EN DIRECT",
                    style: textTheme.labelSmall?.copyWith(color: AppColors.live),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(event.competition.name, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: textTheme.titleLarge),
              if (next != null) ...[
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

class _HighlightCard extends StatefulWidget {
  const _HighlightCard({required this.event});

  final EventSummaryDto event;

  @override
  State<_HighlightCard> createState() => _HighlightCardState();
}

class _HighlightCardState extends State<_HighlightCard> {
  bool _following = false;

  String get _title => widget.event.participants.length == 2
      ? "${widget.event.participants[0].name} – ${widget.event.participants[1].name}"
      : widget.event.name;

  String get _timing {
    final start = widget.event.startsAt.toDateTime;
    if (start == null) return widget.event.competition.name;
    final days = start.toLocal().difference(DateTime.now()).inDays;
    return switch (days) {
      <= 0 => "Aujourd'hui",
      1 => "Demain",
      _ => "Dans $days jours",
    };
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppGradients.highlights[widget.event.id.hashCode.abs() % AppGradients.highlights.length];
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: widget.event.id)),
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
                _FollowPill(following: _following, onTap: () => setState(() => _following = !_following)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Visuel uniquement : les abonnements arrivent au J4, ce bouton ne mémorise
/// rien au-delà de l'écran (pas d'appel réseau, pas de persistance).
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

