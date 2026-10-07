import "../../widgets/ornate_frame.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../../widgets/page_title.dart";
import "../../theme/app_theme.dart";
import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/clock.dart";
import "../../core/date_x.dart";
import "../../core/games.dart";
import "../../core/iterable_x.dart";
import "../../core/navigation.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/avatar_circle.dart";
import "../../widgets/compact_match_row.dart";
import "../../widgets/event_card.dart";
import "../../widgets/game_logo.dart";
import "../../widgets/live_dot.dart";
import "../../widgets/match_context.dart";
import "../../widgets/match_countdown.dart";
import "../../widgets/match_visuals.dart" show TeamLogo;
import "../../widgets/notifications_banner.dart";
import "../account/auth_screen.dart";
import "../competitions/game_screen.dart" show openCompetitionPage;
import "../follows/follows_provider.dart";
import "../follows/follows_screen.dart";
import "../learn/learn_screen.dart";
import "../bracket/bracket_model.dart" show scheduleLabel;
import "grand_final_card.dart";
import "../next_match/next_match_screen.dart";
import "../profile/community_providers.dart";
import "../profile/profile_screen.dart";

final homeProvider = FutureProvider.autoDispose<HomeResponseDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getHomeApi().homeControllerGetHome();
  return response.data!;
});

/// Écran 17 (`docs/02`), refondu au J22 : résumé → matchs en direct (pastilles) → « Maintenant pour toi »
/// (la seule grande carte) → aujourd'hui dans tes suivis (lignes compactes) → grands rendez-vous
/// (mini-cartes) → puce d'apprentissage fermable. Une section sans contenu n'est pas affichée.
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
              AsyncError() => SliverFillRemaining(hasScrollBody: false, child: ErrorState(message: "Impossible de charger l'accueil.", onRetry: () => ref.invalidate(homeProvider))),
              _ => const SliverToBoxAdapter(child: SkeletonCards(count: 5)),
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
    final avatarUrl = ref.watch(pendingAvatarProvider) ?? profile?.avatarUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(capitalized, style: const TextStyle(color: AppColors.textSecondary)),
          Row(
            children: [
              // Une seule ligne : le titre rétrécit plutôt que de passer à la ligne quand les icônes se multiplient.
              Expanded(
                child: FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text("Aujourd'hui", maxLines: 1, style: AppTextStyles.pageTitle)),
              ),
              // Tous les suivis : l'Accueil ne les liste plus (J22), seulement les matchs du jour.
              if (ref.watch(signedInProvider))
                IconButton(
                  tooltip: "Tes suivis",
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowsScreen())),
                  icon: const Icon(Icons.bookmark_border_rounded),
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

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.home, required this.scoresHidden});

  final HomeResponseDto home;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = home.liveNow.toList();
    final upcoming = home.upcoming.toList();
    final grandFinals = home.grandFinals.toList();
    // "Maintenant pour toi" (docs/02, écran 17) : d'abord ce qui est suivi et
    // en direct, sinon le premier direct générique ; si rien n'est en direct,
    // le bandeau retombe sur le prochain match à venir ("à suivre") plutôt que
    // de disparaître.
    final liveEvent = home.nowForYou?.status == "live" ? home.nowForYou : live.firstOrNull;
    final upNextEvent = liveEvent == null ? (home.nowForYou ?? upcoming.firstOrNull) : null;
    // La seule grande carte de l'écran : le match en direct, le prochain match, ou la grande finale
    // quand c'est elle qui est en jeu (son état spécial) ou quand il n'y a rien d'autre.
    final featured = liveEvent ?? upNextEvent ?? grandFinals.firstOrNull?.event;
    final featuredFinal = featured == null ? null : grandFinals.where((g) => g.event.id == featured.id).firstOrNull;

    final summary = homeSummary(home, DateTime.now());
    final todayFollowed = _todayFollowed(home, excluding: featured?.id);
    final livePills = live.where((e) => e.id != featured?.id && e.participants.length == 2).toList();
    // Matchs suivis qui commencent dans moins d'une heure : une pastille avec le compte à rebours (hors grande carte).
    final soon = _startingSoon(home, excluding: featured?.id);
    final yesterday = _yesterdayResults(home);
    final hasFollows = (ref.watch(followsProvider).value ?? const []).isNotEmpty;
    return SliverList(
      delegate: SliverChildListDelegate([
        if (summary != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Text(summary, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (hasFollows) const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.md), child: NotificationsDisabledBanner()),
        if (livePills.isNotEmpty || soon.isNotEmpty) _LivePills(live: livePills, soon: soon),
        if (featured != null)
          _Featured(
            event: featured,
            grandFinal: featuredFinal,
            title: liveEvent != null || home.nowForYou?.id == featured.id ? "Maintenant pour toi" : "À suivre",
            scoresHidden: scoresHidden,
            // « Ensuite » seulement si ce match a lieu aujourd'hui : un match de demain n'est pas « ensuite ».
            next: liveEvent != null ? upcoming.firstOrNull.ifToday : null,
          ),
        _TodayFollowed(events: todayFollowed, scoresHidden: scoresHidden),
        if (yesterday.isNotEmpty) _YesterdayResults(events: yesterday, scoresHidden: scoresHidden),
        if (home.majors.isNotEmpty) _MajorsCarousel(majors: home.majors.toList()),
        const _LearnChip(),
        const SizedBox(height: 96),
      ]),
    );
  }
}

/// Matchs des suivis dont le jour local est aujourd'hui, sauf [excluding] (déjà sur la grande carte).
List<EventSummaryDto> _todayFollowed(HomeResponseDto home, {String? excluding}) {
  final today = dateOnly(DateTime.now());
  return home.todayFollowed.where((e) {
    final at = e.startsAt.toDateTime?.toLocal();
    return e.id != excluding && at != null && dateOnly(at) == today;
  }).toList();
}

/// Matchs suivis à venir qui commencent dans l'heure (et pas encore commencés), sauf [excluding].
List<EventSummaryDto> _startingSoon(HomeResponseDto home, {String? excluding}) {
  final now = DateTime.now();
  return home.todayFollowed.where((e) {
    final at = e.startsAt.toDateTime?.toLocal();
    return e.id != excluding && e.status == "scheduled" && e.participants.length == 2 && at != null && at.isAfter(now) && at.difference(now) <= const Duration(hours: 1);
  }).toList();
}

/// Résultats d'hier (jour local) parmi les suivis : ce qu'on a pu manquer.
List<EventSummaryDto> _yesterdayResults(HomeResponseDto home) {
  final n = DateTime.now();
  final yesterday = DateTime(n.year, n.month, n.day - 1);
  return home.todayFollowed.where((e) {
    final at = e.startsAt.toDateTime?.toLocal();
    return e.status == "finished" && at != null && dateOnly(at) == yesterday;
  }).toList();
}

String _teams(EventSummaryDto e) => e.participants.map((p) => p.shortName ?? p.name).join(" – ");

/// Une ligne qui dit où on en est, par gabarit : « Ton match est en direct : FNC – G2. », « Ton
/// prochain match : FNC – G2, demain à 9 h. », sinon le nombre de matchs en direct ou du jour.
/// `null` quand il n'y a rien à dire (la ligne disparaît).
String? homeSummary(HomeResponseDto home, DateTime now) {
  final mine = home.nowForYou;
  if (mine != null && mine.status == "live") return "Ton match est en direct : ${_teams(mine)}.";
  final start = mine?.startsAt.toDateTime?.toLocal();
  if (mine != null && start != null && !start.isBefore(now)) return "Ton prochain match : ${_teams(mine)}, ${scheduleLabel(start, now)}.";
  final live = home.liveNow.length;
  if (live > 0) return live == 1 ? "1 match en direct." : "$live matchs en direct.";
  final today = home.upcoming.where((e) => e.startsAt.toDateTime != null && dateOnly(e.startsAt.toDateTime!.toLocal()) == dateOnly(now)).length;
  if (today > 0) return today == 1 ? "1 match aujourd'hui." : "$today matchs aujourd'hui.";
  return null;
}

/// Rangée de pastilles façon stories : matchs en direct avec leur score, puis matchs suivis qui commencent dans l'heure
/// avec leur compte à rebours (hors celui de la grande carte).
class _LivePills extends ConsumerWidget {
  const _LivePills({required this.live, required this.soon});

  final List<EventSummaryDto> live;
  final List<EventSummaryDto> soon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        children: [
          for (final e in live) ...[LivePill(event: e), const SizedBox(width: AppSpacing.sm)],
          for (final e in soon) ...[LivePill(event: e, soon: true), const SizedBox(width: AppSpacing.sm)],
        ],
      ),
    );
  }
}

/// Pastille d'un match : en direct (point rouge, logo, score, logo) ou, avec [soon], laiton avec le compte à rebours
/// jusqu'au début. Un appui ouvre le match.
class LivePill extends StatelessWidget {
  const LivePill({super.key, required this.event, this.soon = false});

  final EventSummaryDto event;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final a = event.participants[0];
    final b = event.participants[1];
    final color = soon ? AppColors.brass : AppColors.live;
    Widget logo(EventParticipantDto p) => SizedBox(
      width: 22,
      height: 22,
      child: p.imageUrl == null ? Center(child: Text((p.shortName ?? p.name).characters.first, style: const TextStyle(fontWeight: FontWeight.w700))) : TeamLogo(imageUrl: p.imageUrl!, size: 22),
    );
    final start = event.startsAt.toDateTime?.toLocal();
    return Semantics(
      button: true,
      label: soon ? "${_teams(event)}, commence bientôt" : "${_teams(event)}, en direct",
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.5))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!soon) ...[const LiveDot(size: 7), const SizedBox(width: AppSpacing.sm)],
                logo(a),
                const SizedBox(width: 6),
                if (soon && start != null)
                  MatchCountdown(startsAt: start, fontSize: 15)
                else ...[
                  Text("${a.score?.toInt() ?? 0}", style: AppTextStyles.score(18)),
                  const Text("  –  ", style: TextStyle(color: AppColors.textSecondary)),
                  Text("${b.score?.toInt() ?? 0}", style: AppTextStyles.score(18)),
                ],
                const SizedBox(width: 6),
                logo(b),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Maintenant pour toi » : la seule grande carte de l'Accueil ; la carte de grande finale en est l'état spécial.
class _Featured extends StatelessWidget {
  const _Featured({required this.event, required this.grandFinal, required this.title, required this.scoresHidden, this.next});

  final EventSummaryDto event;
  final GrandFinalDto? grandFinal;
  final String title;
  final bool scoresHidden;
  final EventSummaryDto? next;

  @override
  Widget build(BuildContext context) {
    final live = event.status == "live";
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          if (grandFinal != null)
            GrandFinalCard(grandFinal: grandFinal!)
          else
            EventCard(
              event: event,
              scoresHidden: scoresHidden,
              banner: live,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
              footer: live && next != null
                  ? Text(
                      "Ensuite : ${_teams(next!)}",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gold),
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            ),
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

/// « Aujourd'hui dans tes suivis » : les matchs du jour, en lignes compactes regroupées par compétition.
/// Pour l'invité, une invitation à créer un compte (suivre exige un compte). Rien si la liste est vide.
class _TodayFollowed extends ConsumerWidget {
  const _TodayFollowed({required this.events, required this.scoresHidden});

  final List<EventSummaryDto> events;
  final bool scoresHidden;

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
    if (events.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Aujourd'hui dans tes suivis", style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          for (final (competition, matches) in groupByCompetition(events)) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 6),
              child: MatchContextLine(competition: competition, uppercase: true, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.brass)),
            ),
            for (final event in matches) ...[
              CompactMatchRow(
                event: event,
                scoresHidden: scoresHidden,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}

/// Résultats d'hier de tes suivis, repliés par défaut (scores floutés en sans spoil, comme partout).
class _YesterdayResults extends StatefulWidget {
  const _YesterdayResults({required this.events, required this.scoresHidden});

  final List<EventSummaryDto> events;
  final bool scoresHidden;

  @override
  State<_YesterdayResults> createState() => _YesterdayResultsState();
}

class _YesterdayResultsState extends State<_YesterdayResults> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.events.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(n == 1 ? "HIER · 1 RÉSULTAT" : "HIER · $n RÉSULTATS", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.brass))),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_open)
            for (final event in widget.events) ...[
              CompactMatchRow(
                event: event,
                scoresHidden: widget.scoresHidden,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
              ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}

/// « Les grands rendez-vous » : un carrousel de mini-cartes de tournois importants, en cours ou proches.
class _MajorsCarousel extends StatelessWidget {
  const _MajorsCarousel({required this.majors});

  final List<MajorCompetitionDto> majors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text("Les grands rendez-vous", style: AppTextStyles.sectionTitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: majors.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => MajorCard(major: majors[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini-carte d'un tournoi : logo, nom, « En cours » ou la date du premier match. Un appui ouvre sa page.
class MajorCard extends StatelessWidget {
  const MajorCard({super.key, required this.major});

  final MajorCompetitionDto major;

  @override
  Widget build(BuildContext context) {
    final start = major.startsAt.toDateTime;
    final game = major.game;
    return SizedBox(
      width: 148,
      child: OrnateFrame(
        child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openCompetitionPage(context, id: major.id, name: major.name, status: major.status),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LeagueLogo(imageUrl: major.imageUrl, size: 30),
                    const Spacer(),
                    if (game != null) GameLogo(slug: game, size: 20),
                  ],
                ),
                const Spacer(),
                Text(major.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.versus(15)),
                const SizedBox(height: 2),
                if (major.live)
                  const Row(children: [LiveDot(size: 6), SizedBox(width: 4), Text("En cours", style: TextStyle(fontSize: AppTypography.label, color: AppColors.live))])
                else if (start != null)
                  Text(scheduleLabel(start, DateTime.now()), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Invitation à découvrir un jeu tant que tous les tutos ne sont pas lus, réduite à une puce qu'on peut
/// fermer pour de bon (J22) : « Nouveau sur Valorant ? » (ou LoL) au départ, puis la progression.
class _LearnChip extends ConsumerStatefulWidget {
  const _LearnChip();

  @override
  ConsumerState<_LearnChip> createState() => _LearnChipState();
}

class _LearnChipState extends ConsumerState<_LearnChip> {
  late bool _dismissed = ref.read(authStoreProvider).learnChipDismissed;

  @override
  Widget build(BuildContext context) {
    // Le premier jeu dont il reste des tutos à lire (J23 : Valorant, puis League of Legends).
    String? game;
    ({int read, int total})? progress;
    for (final candidate in learnableGames) {
      final p = learnProgress(ref, candidate);
      if (p != null && p.read < p.total) {
        game = candidate;
        progress = p;
        break;
      }
    }
    if (_dismissed || game == null || progress == null) return const SizedBox.shrink();
    final started = progress.read > 0;
    final name = gameLabel(game);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: AppColors.surface,
          shape: StadiumBorder(side: BorderSide(color: AppColors.brass.withValues(alpha: 0.4))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => openLearnGuide(context, game!),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.help_outline_rounded, size: 18, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text(started ? "$name : ${progress.read}/${progress.total} tutos lus" : "Nouveau sur $name ?", style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: "Fermer",
                onPressed: () {
                  ref.read(authStoreProvider).dismissLearnChip();
                  setState(() => _dismissed = true);
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
