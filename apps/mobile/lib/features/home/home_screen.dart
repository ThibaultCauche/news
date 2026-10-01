import "../../widgets/ornate_frame.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../widgets/page_title.dart";
import "../../theme/app_theme.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/clock.dart";
import "../../core/date_x.dart";
import "../../core/iterable_x.dart";
import "../../core/navigation.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/event_card.dart";
import "../account/auth_screen.dart";
import "../follows/follows_provider.dart";
import "../follows/follows_screen.dart";
import "../learn/learn_screen.dart";
import "../learn/learn_visuals.dart";
import "grand_final_card.dart";
import "../next_match/next_match_screen.dart";
import "../profile/community_providers.dart";
import "../profile/profile_screen.dart";

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
              // Pendant un rechargement automatique, on garde l'ancien contenu (pas de spinner).
              _ when home.hasValue => _HomeBody(home: home.value!, scoresHidden: scoresHidden),
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
    final date = DateFormat("EEEE d MMMM", "fr_FR").format(ref.watch(todayProvider));
    final capitalized = date[0].toUpperCase() + date.substring(1);
    final profile = ref.watch(profileProvider).value;
    final pseudo = profile?.pseudo;
    final avatarUrl = profile?.avatarUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(capitalized, style: const TextStyle(color: AppColors.textSecondary)),
          Row(
            children: [
              Expanded(child: Text("Aujourd'hui", style: AppTextStyles.pageTitle)),
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
              // Le profil (J11) : initiale du pseudo une fois créé, silhouette pour l'invité.
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: AvatarCircle(avatarUrl: avatarUrl, pseudo: pseudo, radius: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const BrassRule(),
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
        // « Ensuite » seulement si ce match a lieu aujourd'hui : un match de demain n'est pas « ensuite ».
        if (liveEvent != null) _LiveBanner(event: liveEvent, scoresHidden: scoresHidden, next: upcoming.firstOrNull.ifToday),
        if (liveEvent == null && upNextEvent != null) _UpNextSection(event: upNextEvent, scoresHidden: scoresHidden),
        if (grandFinals.isNotEmpty) _GrandFinalsSection(grandFinals: grandFinals),
        const _FollowsSection(),
        const _LearnCard(),
        const SizedBox(height: AppSpacing.xl),
      ]),
    );
  }
}

/// "Maintenant pour toi" (docs/02, écran 17) : le match en direct sur la carte de match commune
/// (`EventCard`, logos et scores), teintée en rouge, avec le match suivant en dessous en or.
class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.event, required this.scoresHidden, this.next});

  final EventSummaryDto event;
  final bool scoresHidden;
  final EventSummaryDto? next;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: EventCard(
        event: event,
        scoresHidden: scoresHidden,
        banner: true,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
        footer: next == null
            ? null
            : Text(
                "Ensuite : ${next!.participants.map((p) => p.shortName ?? p.name).join(" – ")}",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gold),
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}

/// "À suivre" (rien n'est en direct) : le prochain match, sur la même carte que
/// partout ailleurs (`EventCard`).
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
          Text("À suivre", style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          EventCard(
            event: event,
            scoresHidden: scoresHidden,
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
          Text("Les grands rendez-vous", style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(child: SvgPicture.asset("assets/ornaments/rule.svg", width: 120)),
          const SizedBox(height: AppSpacing.sm),
          for (final grandFinal in grandFinals) GrandFinalCard(grandFinal: grandFinal),
        ],
      ),
    );
  }
}

extension _NextToday on EventSummaryDto? {
  /// Ce match s'il commence aujourd'hui (heure locale), sinon `null`.
  EventSummaryDto? get ifToday {
    final start = this?.startsAt.toDateTime?.toLocal();
    if (start == null) return null;
    return dateOnly(start) == dateOnly(DateTime.now()) ? this : null;
  }
}


/// « Tes suivis » (écran 17, `docs/02`), de retour sur l'Accueil au J11 quand l'onglet Suivis a
/// disparu : les trois premiers suivis avec leur prochain match, « Tout voir » ouvre l'écran
/// complet. Pour l'invité, une invitation à créer un compte (suivre exige un compte).
class _FollowsSection extends ConsumerWidget {
  const _FollowsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(signedInProvider)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
        child: FramedCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Tes suivis", style: AppTextStyles.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                const Text("Crée un compte pour suivre tes équipes et compétitions et être alerté.", style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
                  child: const Text("Créer un compte"),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Un match suivi déjà terminé n'a plus rien à montrer ici (pas de « prochain match »).
    final follows = (ref.watch(followsProvider).value ?? const [])
        .where((f) => !f.muted && !(f.targetType == "event" && f.currentEvent?.status != "scheduled" && f.currentEvent?.status != "live"))
        .toList();
    if (follows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text("Tes suivis", style: AppTextStyles.sectionTitle)),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowsScreen())),
                child: const Text("Tout voir"),
              ),
            ],
          ),
          for (final follow in follows.take(3)) ...[
            FollowCard(follow: follow, targetType: followTargetTypeFromWire(follow.targetType)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Invitation à découvrir Valorant tant que tous les tutos ne sont pas lus : « Nouveau sur
/// Valorant ? » au départ, puis la progression. Disparaît une fois tout lu.
class _LearnCard extends ConsumerWidget {
  const _LearnCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = learnProgress(ref, "valorant");
    if (progress == null || progress.read >= progress.total) return const SizedBox.shrink();
    final started = progress.read > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: FramedCard(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const LearnIconTile(icon: Icons.sports_esports_rounded, gradient: 0),
          title: Text(started ? "Continue d'apprendre Valorant" : "Nouveau sur Valorant ?", style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            started ? "${progress.read}/${progress.total} tutos lus" : "Comprends un match en quelques minutes.",
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => openLearnGuide(context, "valorant"),
        ),
      ),
    );
  }
}
