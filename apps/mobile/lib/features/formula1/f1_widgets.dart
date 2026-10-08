import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/date_x.dart";
import "../../core/settings_provider.dart";
import "../../domain/event_status.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/event_card.dart" show EventAlertBell;
import "../../widgets/live_badge.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/section_card.dart";
import "../../widgets/section_label.dart";
import "../../widgets/spoiler_hold.dart";
import "../../widgets/competition_follow_button.dart";
import "../../widgets/compact_match_row.dart";
import "../../widgets/follow_button.dart";
import "../bracket/bracket_provider.dart";
import "../follows/follows_provider.dart";
import "../competitions/game_screen.dart" show SeasonTabs;
import "../discussion/share_sheet.dart";
import "../learn/learn_screen.dart";
import "../competitions/competitions_data.dart" show formatDateRange;
import "../next_match/next_match_screen.dart";
import "../team/team_screen.dart";
import "f1_model.dart";

/// Saison de F1 à montrer pour un jeu du catalogue : celle en cours, sinon la plus récente.
String? f1SeasonId(CatalogGameDto game) {
  final seasons = [for (final league in game.leagues) ...league.children]..sort((a, b) => (b.startsAt ?? "").compareTo(a.startsAt ?? ""));
  if (seasons.isEmpty) return null;
  return (seasons.where((s) => s.live).firstOrNull ?? seasons.first).id;
}

/// Podium d'une session (« RUS · ANT · LEC »), flouté en sans spoil et révélé par appui long, comme un score.
class SessionPodium extends ConsumerWidget {
  const SessionPodium({super.key, required this.event, this.style});

  final EventSummaryDto event;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = podiumLabel(event.participants.toList());
    if (label.isEmpty) return const SizedBox.shrink();
    final hidden = ref.watch(scoreHiddenProvider(event.id));
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? AppTextStyles.captionStrong);
    if (!hidden) return text;
    return SpoilerHold(builder: (context, sigma) => SpoilerBlur(sigma: sigma, child: text), onReveal: () => ref.read(revealedEventsProvider.notifier).reveal(event.id));
  }
}

String _dayAndTime(String? iso) {
  final start = iso.toDateTime?.toLocal();
  if (start == null) return "";
  return "${DateFormat("EEE d MMM", "fr_FR").format(start)} · ${DateFormat.Hm("fr_FR").format(start)}";
}

/// Page d'une saison de F1 (J28), ouverte depuis une carte de l'Accueil, d'une page de compétition ou de l'écran d'une
/// session : Calendrier, Pilotes, Constructeurs. La page du jeu (`GameScreen`) montre les mêmes onglets.
class F1SeasonScreen extends ConsumerStatefulWidget {
  const F1SeasonScreen({super.key, required this.competitionId, required this.title});

  final String competitionId;
  final String title;

  @override
  ConsumerState<F1SeasonScreen> createState() => _F1SeasonScreenState();
}

class _F1SeasonScreenState extends ConsumerState<F1SeasonScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          const LearnHelpButton(articleId: "le-jeu", game: "formula-1"),
          ShareButton(kind: ShareDtoKindEnum.competition, refId: widget.competitionId),
          CompetitionFollowButton(competitionId: widget.competitionId, name: widget.title),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le titre est dans la page, pas dans la barre : avec trois actions, la barre le coupait (« FORMU… »).
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(widget.title, maxLines: 1, style: AppTextStyles.pageTitle)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: SeasonTabs(labels: const ["Calendrier", "Pilotes", "Écuries"], selectedIndex: _tab, onSelected: (i) => setState(() => _tab = i)),
          ),
          Expanded(
            child: switch (_tab) {
              0 => F1CalendarTab(seasonId: widget.competitionId),
              1 => F1StandingsTab(seasonId: widget.competitionId, constructors: false),
              _ => F1StandingsTab(seasonId: widget.competitionId, constructors: true),
            },
          ),
        ],
      ),
    );
  }
}

/// Onglet « Calendrier » de la page F1 : les Grands Prix de la saison, le prochain mis en avant.
class F1CalendarTab extends ConsumerWidget {
  const F1CalendarTab({super.key, required this.seasonId});

  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonId = this.seasonId;
    if (seasonId == null) return const Center(child: Text("Aucune saison pour l'instant.", style: TextStyle(color: AppColors.textSecondary)));
    return AsyncView(
      value: ref.watch(competitionDetailProvider(seasonId)),
      errorMessage: "Impossible de charger le calendrier.",
      onRetry: () => ref.invalidate(competitionDetailProvider(seasonId)),
      builder: (season) {
        final races = season.children.where((c) => c.kind == "tournament").toList()..sort((a, b) => (a.startsAt ?? "").compareTo(b.startsAt ?? ""));
        final next = races.indexWhere((r) => r.status != "finished");
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
          children: [
            SectionLabel("SAISON ${RegExp(r"\d{4}").firstMatch(season.name)?.group(0) ?? ""} ·${races.length} GRANDS PRIX"),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, race) in races.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _RaceTile(round: i + 1, race: race, highlight: i == next),
              ),
          ],
        );
      },
    );
  }
}

class _RaceTile extends StatelessWidget {
  const _RaceTile({required this.round, required this.race, required this.highlight});

  final int round;
  final CompetitionChildDto race;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final live = race.status == "live";
    final finished = race.status == "finished";
    return OrnateFrame(
      radius: AppRadii.card,
      color: live ? AppColors.live : AppColors.brass,
      strong: highlight || live,
      child: Material(
        color: live ? AppColors.live.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrandPrixScreen(competitionId: race.id, title: grandPrixName(race.name)))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
            child: Row(
              children: [
                SizedBox(width: 34, child: Text("$round", style: AppTextStyles.versus(20).copyWith(color: finished ? AppColors.textTertiary : AppColors.brass))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: Text(grandPrixName(race.name), style: AppTextStyles.bodyLargeStrong, maxLines: 1))),
                      const SizedBox(height: 2),
                      Text(formatDateRange(race.startsAt, race.endsAt) ?? "", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                      if (live || highlight) ...[const SizedBox(height: 4), live ? const Stamp("EN DIRECT", fontSize: 9) : const Stamp("PROCHAIN", color: AppColors.brass, fontSize: 9)],
                    ],
                  ),
                ),
                if (finished) const Icon(Icons.check_rounded, size: 18, color: AppColors.textTertiary),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onglets « Pilotes » et « Constructeurs » : le classement du championnat tel que la source le donne.
class F1StandingsTab extends ConsumerWidget {
  const F1StandingsTab({super.key, required this.seasonId, required this.constructors});

  final String? seasonId;
  final bool constructors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonId = this.seasonId;
    if (seasonId == null) return const Center(child: Text("Aucune saison pour l'instant.", style: TextStyle(color: AppColors.textSecondary)));
    return AsyncView(
      value: ref.watch(competitionDetailProvider(seasonId)),
      errorMessage: "Impossible de charger le classement.",
      onRetry: () => ref.invalidate(competitionDetailProvider(seasonId)),
      builder: (season) {
        final rows = season.standings.where((s) => (s.entityKind == "constructor") == constructors).toList()..sort((a, b) => (a.rank ?? 99).compareTo(b.rank ?? 99));
        if (rows.isEmpty) return Center(child: Text("Le classement apparaît après la première course.", style: TextStyle(color: AppColors.textSecondary)));
        // Le classement dit qui mène : masqué en sans spoil, comme un score, jusqu'à « Afficher ».
        return _StandingsList(rows: rows, constructors: constructors);
      },
    );
  }
}

class _StandingsList extends ConsumerStatefulWidget {
  const _StandingsList({required this.rows, required this.constructors});

  final List<CompetitionStandingDto> rows;
  final bool constructors;

  @override
  ConsumerState<_StandingsList> createState() => _StandingsListState();
}

class _StandingsListState extends ConsumerState<_StandingsList> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final hidden = (ref.watch(userSettingProvider).value?.spoilerFree ?? true) && !_revealed;
    final list = SectionCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (final (i, row) in widget.rows.indexed) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
            _StandingRow(row: row, constructors: widget.constructors),
          ],
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        SectionLabel(widget.constructors ? "CHAMPIONNAT DES CONSTRUCTEURS" : "CHAMPIONNAT DES PILOTES"),
        const SizedBox(height: AppSpacing.sm),
        // La consigne est au-dessus de la liste : en dessous, une vingtaine de lignes floutées la cacheraient.
        if (hidden) ...[
          const Center(child: Text("Maintiens pour révéler le classement", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
          const SizedBox(height: AppSpacing.sm),
          SpoilerHold(builder: (context, sigma) => SpoilerBlur(sigma: sigma, child: list), onReveal: () => setState(() => _revealed = true)),
        ] else
          list,
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.row, required this.constructors});

  final CompetitionStandingDto row;
  final bool constructors;

  @override
  Widget build(BuildContext context) {
    final points = row.points;
    final wins = row.wins ?? 0;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(entityId: row.entityId, breadcrumb: "Formule 1"))),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text("${row.rank ?? "–"}", style: AppTextStyles.versus(16).copyWith(color: (row.rank ?? 99) <= 3 ? AppColors.brass : AppColors.textSecondary))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.entityName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong),
                if (wins > 0) Text("$wins ${wins > 1 ? "victoires" : "victoire"}", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
          SizedBox(width: 52, child: Text(points == null ? "" : _points(points), textAlign: TextAlign.right, style: AppTextStyles.score(17))),
        ],
      ),
    ),
    );
  }

  static String _points(num value) => value == value.roundToDouble() ? "${value.toInt()}" : value.toString();
}

/// Page d'un week-end de Grand Prix : ses sessions dans l'ordre, avec le podium des sessions terminées.
class GrandPrixScreen extends ConsumerWidget {
  const GrandPrixScreen({super.key, required this.competitionId, required this.title});

  final String competitionId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: FittedBox(fit: BoxFit.scaleDown, child: Text(title, maxLines: 1))),
      body: AsyncView(
        value: ref.watch(competitionDetailProvider(competitionId)),
        errorMessage: "Impossible de charger ce Grand Prix.",
        onRetry: () => ref.invalidate(competitionDetailProvider(competitionId)),
        builder: (gp) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
          children: [
            SectionLabel(formatDateRange(gp.startsAt, gp.endsAt)?.toUpperCase() ?? "WEEK-END"),
            if (gp.location != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(gp.location!, style: const TextStyle(color: AppColors.textSecondary))),
            const SizedBox(height: AppSpacing.sm),
            if (gp.events.isEmpty) const Text("Le programme du week-end n'est pas encore connu.", style: TextStyle(color: AppColors.textSecondary)),
            for (final session in gp.events)
              Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: SessionTile(event: session)),
          ],
        ),
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.event});

  final EventSummaryDto event;

  @override
  Widget build(BuildContext context) {
    final status = event.status.statusKind;
    final live = status == EventStatusKind.live;
    return OrnateFrame(
      radius: AppRadii.card,
      color: live ? AppColors.live : AppColors.brass,
      strong: event.name == "Course",
      child: Material(
        color: live ? AppColors.live.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.name, style: AppTextStyles.bodyLargeStrong),
                      const SizedBox(height: 2),
                      Text(_dayAndTime(event.startsAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                      if (status == EventStatusKind.finished && event.participants.isNotEmpty) ...[const SizedBox(height: 4), SessionPodium(event: event)],
                    ],
                  ),
                ),
                if (live) const Stamp("EN DIRECT", fontSize: 9) else if (status == EventStatusKind.scheduled) EventAlertBell(eventId: event.id) else if (status == EventStatusKind.finished) const Icon(Icons.check_rounded, size: 18, color: AppColors.textTertiary),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Écran d'une session de F1 (essais, qualifications, sprint, course) : en-tête, podium, arrivée complète. Même
/// logique de spoil qu'un score : le classement d'une session terminée est flouté et se révèle par appui long.
class SessionBody extends ConsumerWidget {
  const SessionBody({super.key, required this.event, required this.scoresHidden, required this.onReveal});

  final EventDetailResponseDto event;
  final bool scoresHidden;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = event.status.statusKind;
    final finished = status == EventStatusKind.finished;
    final rows = event.classification.toList();
    final qualifying = isQualifying(event.name);
    final winnerLaps = rows.isEmpty ? null : rows.first.laps;

    final results = rows.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Podium(rows: rows.take(3).toList()),
              const SizedBox(height: AppSpacing.md),
              SectionLabel(qualifying ? "QUALIFICATIONS" : "ARRIVÉE"),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (final (i, row) in rows.indexed) ...[
                      if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                      _ClassificationRow(row: row, qualifying: qualifying, winnerLaps: winnerLaps),
                    ],
                  ],
                ),
              ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        OrnateFrame(
          strong: event.name == "Course",
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), color: AppColors.surface),
            child: Column(
              children: [
                Text(grandPrixName(event.competition.name).toUpperCase(), textAlign: TextAlign.center, style: AppTextStyles.sectionTitle.copyWith(fontSize: 14, letterSpacing: 1.2)),
                const SizedBox(height: AppSpacing.sm),
                Text(event.name, style: AppTextStyles.pageTitle),
                const SizedBox(height: AppSpacing.sm),
                if (status == EventStatusKind.live)
                  const Stamp("EN DIRECT")
                else
                  Text(_dayAndTime(event.startsAt), style: const TextStyle(color: AppColors.textSecondary)),
                if (status == EventStatusKind.scheduled) ...[const SizedBox(height: AppSpacing.sm), EventAlertBell(eventId: event.id)],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (results == null)
          Text(
            !hasClassification(event.name)
                ? "Les essais libres n'ont pas de classement ici : ils servent aux équipes à régler leur voiture."
                : finished
                ? "Le classement arrive dans quelques minutes."
                : "Le classement sera publié après la session.",
            style: const TextStyle(color: AppColors.textSecondary),
          )
        else if (scoresHidden && finished) ...[
          // La consigne est au-dessus : sous 22 lignes floutées, on ne la verrait jamais.
          const Center(child: Text("Maintiens pour révéler le classement", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
          const SizedBox(height: AppSpacing.sm),
          SpoilerHold(builder: (context, sigma) => SpoilerBlur(sigma: sigma, child: results), onReveal: () {
            ref.read(revealedEventsProvider.notifier).reveal(event.id);
            onReveal();
          }),
        ] else
          results,
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.rows});

  final List<ClassificationRowDto> rows;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: SectionCard(
                highlight: row.position == 1,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
                child: Column(
                  children: [
                    Text("${row.position}", style: AppTextStyles.heroScore.copyWith(fontSize: 30, color: row.position == 1 ? AppColors.gold : AppColors.brass)),
                    const SizedBox(height: 2),
                    Text(row.code ?? row.name, style: AppTextStyles.bodyLargeStrong),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(row.constructorName ?? "", maxLines: 1, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ClassificationRow extends StatelessWidget {
  const _ClassificationRow({required this.row, required this.qualifying, this.winnerLaps});

  final ClassificationRowDto row;
  final bool qualifying;
  final num? winnerLaps;

  @override
  Widget build(BuildContext context) {
    final detail = qualifying ? (qualifyingTime(row) ?? "") : gapLabel(row, winnerLaps: winnerLaps);
    final points = row.points;
    final out = !qualifying && row.positionText != "${row.position}";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 38, child: Text(positionLabel(row), style: AppTextStyles.versus(out ? 12 : 15).copyWith(color: out ? AppColors.textTertiary : AppColors.textPrimary))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyStrong),
                if (row.constructorName != null) Text(row.constructorName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
              ],
            ),
          ),
          Text(detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
          if (!qualifying && points != null && points > 0) SizedBox(width: 44, child: Text("+${points.toInt()}", textAlign: TextAlign.right, style: AppTextStyles.score(14).copyWith(color: AppColors.brass))) else if (!qualifying) const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// Fiche d'un pilote ou d'une écurie (J28) : suivre, place au championnat (donnée par la source, masquée en sans spoil
/// comme un classement), dernière session. Suivre un pilote prévient de ses résultats ; suivre une écurie, de ceux de
/// ses deux pilotes. Il n'y a pas d'avertissement de début : on ne connaît la grille qu'après la session.
class ChampionshipEntityBody extends ConsumerStatefulWidget {
  const ChampionshipEntityBody({super.key, required this.entity, required this.scoresHidden});

  final EntityResponseDto entity;
  final bool scoresHidden;

  @override
  ConsumerState<ChampionshipEntityBody> createState() => _ChampionshipEntityBodyState();
}

class _ChampionshipEntityBodyState extends ConsumerState<ChampionshipEntityBody> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final entity = widget.entity;
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.entity, entity.id);
    final raw = entity.shortName ?? entity.name;
    final initials = (raw.length <= 3 ? raw : raw.substring(0, 3)).toUpperCase();
    final championship = entity.championships.firstOrNull;
    final hidden = widget.scoresHidden && !_revealed;
    final constructor = entity.kind == "constructor";

    final stats = championship == null
        ? null
        : Row(
            children: [
              Expanded(child: _Stat(label: "Classement", value: championship.rank == null ? "–" : "${championship.rank}")),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: _Stat(label: "Points", value: "${championship.points.toInt()}")),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(child: _Stat(label: "Victoires", value: "${championship.wins ?? 0}")),
            ],
          );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.surface, child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Le nom tient sur une ligne : il rétrécit plutôt que de se couper à côté du bouton (« MERCEDE / S »).
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(entity.name, maxLines: 1, style: AppTextStyles.pageTitle)),
                  Text(constructor ? "Écurie" : "Pilote", style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            FollowButton(
              following: following,
              onPressed: () => runOrShowError(
                context,
                () => following
                    ? ref.read(followsControllerProvider).unfollow(FollowTargetType.entity, entity.id)
                    : ref.read(followsControllerProvider).follow(FollowTargetType.entity, entity.id, name: entity.name),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          constructor ? "Suivre cette écurie : tu es prévenu du résultat des courses de ses pilotes." : "Suivre ce pilote : tu es prévenu du résultat de ses courses.",
          style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
        ),
        if (stats != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionLabel("CHAMPIONNAT · ${championship!.competitionName}".toUpperCase()),
          const SizedBox(height: AppSpacing.sm),
          if (hidden) ...[
            const Center(child: Text("Maintiens pour révéler le classement", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
            const SizedBox(height: AppSpacing.sm),
            SpoilerHold(builder: (context, sigma) => SpoilerBlur(sigma: sigma, child: stats), onReveal: () => setState(() => _revealed = true)),
          ] else
            stats,
        ],
        if (entity.lastEvent != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel("DERNIÈRE SESSION"),
          const SizedBox(height: AppSpacing.sm),
          CompactMatchRow(
            event: entity.lastEvent!,
            scoresHidden: widget.scoresHidden,
            followedEntityIds: {entity.id},
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: entity.lastEvent!.id))),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.heroScore.copyWith(fontSize: 26)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption))),
        ],
      ),
    );
  }
}
