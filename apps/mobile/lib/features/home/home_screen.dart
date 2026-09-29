import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";
import "../../core/iterable_x.dart";
import "../../core/navigation.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../../widgets/live_dot.dart";
import "grand_final_card.dart";
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

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Ouvre l'onglet Compétitions avec le curseur dans sa recherche (J10) : pas
          // de second écran de recherche.
          IconButton(
            tooltip: "Rechercher",
            onPressed: () {
              ref.read(tabIndexProvider.notifier).select(competitionsTabIndex);
              ref.read(searchFocusRequestProvider.notifier).request();
            },
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
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.home, required this.scoresHidden});

  final HomeResponseDto home;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    final live = home.liveNow.toList();
    final upcoming = home.upcoming.toList();
    final grandFinals = home.grandFinals.toList();
    // "Maintenant pour toi" (docs/02, écran 17) : d'abord ce qui est suivi et
    // en direct, sinon le premier direct générique ; si rien n'est en direct,
    // le bandeau retombe sur le prochain match à venir ("à suivre") plutôt que
    // de disparaître.
    final liveEvent = home.nowForYou?.status == "live" ? home.nowForYou : live.firstOrNull;
    final upNextEvent = liveEvent == null ? (home.nowForYou ?? upcoming.firstOrNull) : null;

    return SliverList(
      delegate: SliverChildListDelegate([
        if (liveEvent != null) _LiveBanner(event: liveEvent, next: upcoming.firstOrNull),
        if (liveEvent == null && upNextEvent != null) _UpNextSection(event: upNextEvent, scoresHidden: scoresHidden),
        if (grandFinals.isNotEmpty) _GrandFinalsSection(grandFinals: grandFinals),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

/// "Maintenant pour toi" (docs/02, écran 17) : le match en direct, en rouge
/// (règle 12 de `CLAUDE.md`), avec le suivant en dessous.
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
                  Text("EN DIRECT", style: textTheme.labelSmall?.copyWith(color: AppColors.live)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(event.competition.name, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: textTheme.titleLarge),
              if (next != null) ...[
                const Divider(height: AppSpacing.lg),
                Text(
                  "Ensuite : ${next!.participants.map((p) => p.shortName ?? p.name).join(" – ")}",
                  style: textTheme.bodySmall?.copyWith(color: AppColors.gold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "À suivre" (rien n'est en direct) : le prochain match, sur la même carte que
/// partout ailleurs (`EventCard`), avec un compte à rebours à la place du "VS".
class _UpNextSection extends StatelessWidget {
  const _UpNextSection({required this.event, required this.scoresHidden});

  final EventSummaryDto event;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("À suivre", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          EventCard(
            event: event,
            scoresHidden: scoresHidden,
            showCountdown: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
          ),
        ],
      ),
    );
  }
}

/// "Les grands rendez-vous" : la grande finale de la phase finale en cours, la
/// section disparaît hors phase finale (`home.grandFinals` vide).
class _GrandFinalsSection extends StatelessWidget {
  const _GrandFinalsSection({required this.grandFinals});

  final List<GrandFinalDto> grandFinals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Les grands rendez-vous", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final grandFinal in grandFinals) GrandFinalCard(grandFinal: grandFinal),
        ],
      ),
    );
  }
}
