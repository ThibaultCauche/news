import "../discussion/share_sheet.dart";
import "../../widgets/empty_mark.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/games.dart";
import "../../core/iterable_x.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../forum/forum_entry.dart";
import "../learn/learn_screen.dart";
import "../../widgets/async_view.dart";
import "../../widgets/competition_favorite_button.dart";
import "../../widgets/competition_follow_button.dart";
import "../../widgets/group_bracket_tree.dart";
import "../follows/follows_provider.dart";
import "../../widgets/bracket_match_card.dart";
import "../../widgets/horizontal_bracket.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/spoiler_hold.dart";
import "pickem.dart";
import "radial_bracket.dart";
import "bracket_model.dart";
import "bracket_view.dart";
import "bracket_provider.dart";
import "ranking_view.dart";

/// Écrans 02 (arbre radial), 05 (repêchage) et 07 (arbre terminé) — `docs/02`.
/// `competitionId` est le niveau "Champions 2026" (la série) : ses enfants
/// (`competitions/:id`) donnent les poules (« Group … ») et le tournoi à
/// élimination (« Playoffs »), chacun avec son propre bracket/classement.
class BracketScreen extends ConsumerStatefulWidget {
  const BracketScreen({super.key, required this.competitionId, required this.title, required this.subtitle});

  final String competitionId;
  final String title;
  final String subtitle;

  @override
  ConsumerState<BracketScreen> createState() => _BracketScreenState();
}

class _BracketScreenState extends ConsumerState<BracketScreen> {
  /// `null` tant que la personne n'a pas touché aux onglets : l'écran choisit alors selon l'avancement du tournoi.
  int? _chosenTab;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(competitionDetailProvider(widget.competitionId));
    final game = detail.value?.game ?? "valorant";

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: Text(gameLabel(game), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        actions: [
          LearnHelpButton(articleId: "regarder-un-match", game: game),
          ShareButton(kind: ShareDtoKindEnum.competition, refId: widget.competitionId),
          ForumActionButton(kind: "competition", targetId: widget.competitionId),
          CompetitionFavoriteButton(competitionId: widget.competitionId, name: widget.title),
          CompetitionFollowButton(competitionId: widget.competitionId, name: widget.title)],
      ),
      body: AsyncView(
        value: detail,
        errorMessage: "Impossible de charger cette compétition.",
        onRetry: () => ref.invalidate(competitionDetailProvider(widget.competitionId)),
        builder: (value) => _BracketBody(
          competitionId: widget.competitionId,
          title: widget.title,
          subtitle: widget.subtitle,
          children: value.children.toList(),
          chosenTab: _chosenTab,
          onTabSelected: (i) => setState(() => _chosenTab = i),
        ),
      ),
    );
  }
}

class _BracketBody extends ConsumerWidget {
  const _BracketBody({
    required this.competitionId,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.chosenTab,
    required this.onTabSelected,
  });

  final String competitionId;
  final String title;
  final String subtitle;
  final List<CompetitionChildDto> children;
  final int? chosenTab;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupIds = groupCompetitionIds(children);
    final playoffs = children.firstWhereOrNull((c) => c.name.toLowerCase().contains("playoff"));
    final playoffsBracket = playoffs == null ? null : ref.watch(bracketProvider(playoffs.id)).value;
    // Un tableau à simple élimination (Worlds, MSI…) n'a pas de repêchage : l'onglet serait toujours vide.
    final hasLower = playoffsBracket?.format != "single_elim";
    var tabIndex = chosenTab ??
        defaultBracketTab(
          groups: [for (final id in groupIds) ref.watch(bracketProvider(id)).value],
          playoffs: playoffsBracket,
        );
    if (!hasLower && tabIndex == _lowerTab) tabIndex = _finalsTab;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Les deux ronds sont centrés sur la ligne du titre, et leur bord droit s'aligne sur celui
              // du bouton « Suivre » au-dessus.
              Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineMedium)),
                  const BracketViewToggle(),
                ],
              ),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _BracketTabs(selectedIndex: tabIndex, onSelected: onTabSelected, showLower: hasLower),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: switch (tabIndex) {
            _groupsTab => _GroupsTab(groupIds: groupIds),
            _finalsTab => playoffs == null
                ? const _EmptyMessage("Phase finale pas encore commencée.")
                : _FinalsTab(competitionId: playoffs.id),
            _rankingTab => RankingView(competitionId: competitionId),
            _ => playoffs == null
                ? const _EmptyMessage("Repêchage pas encore commencé.")
                : _RepechageTab(competitionId: playoffs.id),
          },
        ),
      ],
    );
  }
}

// Indices des onglets : 0, 1 et 2 sont ceux de `defaultBracketTab` ; le classement global (J23) vient après.
const _groupsTab = 0;
const _finalsTab = 1;
const _lowerTab = 2;
const _rankingTab = 3;

class _BracketTabs extends StatelessWidget {
  const _BracketTabs({required this.selectedIndex, required this.onSelected, required this.showLower});

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showLower;
  static const _allLabels = ["Groupes", "Phase finale", "Repêchage", "Classement"];

  @override
  Widget build(BuildContext context) {
    // (indice de l'onglet, libellé) : sans repêchage, les indices ne se suivent plus.
    final tabs = [for (var i = 0; i < _allLabels.length; i++) if (showLower || i != _lowerTab) (i, _allLabels[i])];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(
        children: [
          for (final (i, label) in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: AppMotion.microDuration,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: selectedIndex == i ? AppColors.glass : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selectedIndex == i ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: selectedIndex == i ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(child: EmptyMark(text));
}

/// Écran 06 : l'arbre de qualification de chaque poule (Ouverture →
/// Vainqueurs/Élimination → Decider → Qualifiés), pas juste un classement —
/// même widget que la carte "Maintenant" de l'écran Saison (`GroupBracketTree`).
class _GroupsTab extends ConsumerWidget {
  const _GroupsTab({required this.groupIds});
  final List<String> groupIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groupIds.isEmpty) return const _EmptyMessage("Pas de phase de groupes pour cette compétition.");
    final live = {
      for (final id in groupIds)
        if (ref.watch(bracketProvider(id)).value?.nodes.any((n) => n.status == "live") ?? false) id,
    };
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final id in liveGroupsFirst(groupIds, live)) GroupBracketTree(competitionId: id, followViewPreference: true),
      ],
    );
  }
}

/// Écran 02/07 : arbre radial par équipes (le tableau haut + le match décisif ; le tableau
/// bas vit dans l'onglet Repêchage), avec en tête la phrase de chaque équipe suivie.
class _FinalsTab extends ConsumerWidget {
  const _FinalsTab({required this.competitionId});
  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bracket = ref.watch(bracketProvider(competitionId));
    final follows = ref.watch(followsProvider).value;

    return Column(
      children: [
        PickemCard(competitionId: competitionId),
        Expanded(
          child: AsyncView(
            value: bracket,
            errorMessage: "Impossible de charger l'arbre.",
            onRetry: () => ref.invalidate(bracketProvider(competitionId)),
            skeleton: const Center(child: Skeleton(width: 280, height: 280, radius: 140)),
            builder: (value) => _FinalsView(bracket: value, follows: follows),
          ),
        ),
      ],
    );
  }
}

class _FinalsView extends ConsumerWidget {
  const _FinalsView({required this.bracket, required this.follows});
  final BracketResponseDto bracket;
  final List<FollowStateDto>? follows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = (follows ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    final circle = ref.watch(bracketViewProvider) == BracketView.circle;
    // En cercle : le tableau principal en haut, le repêchage en bas, séparés par une ligne.
    final lowerIds = {for (final n in bracket.nodes) if (isLowerBracketName(n.name)) n.eventId};
    // Le perdant de la finale du haut rejoint la finale du repêchage : son cercle n'est pas dessiné (le match est déjà en haut),
    // ce qui laisse le bas du cercle aussi net que le haut.
    final lowerFinal = lowerFinalId(bracket);
    final tree = buildRadialTree(
      bracket,
      includeLower: lowerIds.isNotEmpty,
      loserTargets: {...lowerIds}..remove(lowerFinal),
      omitLeaves: {?lowerFinal},
    );
    final halves = mainAndLowerHalves(tree, bracket);
    // Le repêchage : sa seconde moitié reflète la première, pour une symétrie verticale parfaite.
    if (halves != null) assignSectors(tree, halves, mirrored: {?lowerFinal});
    final lines = followedTeamLines(bracket, followed, DateTime.now());
    if (tree.center == null) return const _EmptyMessage("Phase finale pas encore commencée.");

    final legend = const Text(
      "En or, l'équipe que tu suis. En rouge, le match en direct. Touche un cercle pour ouvrir son match.",
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
    final headlines = [
      for (final line in lines)
        Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _TeamLineCard(line: line)),
    ];
    final stakes = [
      for (final line in lines)
        if (line.stakes != null)
          Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(line.stakes!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
    ];

    if (circle) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ...headlines,
          if (tree.slots.isNotEmpty) RadialBracket(
            tree: tree,
            followed: followed,
            center: CenterLabel(node: tree.center!),
            divider: halves == null ? null : (top: "TABLEAU PRINCIPAL", bottom: "REPÊCHAGE"),
            dividerOutside: true,
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm), child: legend),
          ...stakes,
        ],
      );
    }
    // Pyramide : le dessin prend toute la hauteur et se déplace dans tous les sens (le texte
    // d'enjeu reste dessous, sans faire défiler la page par-dessus le geste).
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...headlines,
          Expanded(child: ClipRect(child: HorizontalBracket(bracket: bracket, followed: followed, pannable: true))),
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 96), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: stakes))),
        ],
      ),
    );
  }
}

class _TeamLineCard extends StatelessWidget {
  const _TeamLineCard({required this.line});
  final TeamLine line;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: line.matchId == null ? null : () => openMatch(context, line.matchId!),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.chip), border: Border.all(color: AppColors.gold)),
          child: Text(line.headline, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Écran 05 : tours du repêchage, avec des noms lisibles tant que les équipes ne sont pas
/// connues (« Perdant du quart de finale 1 ») et le nombre de vies de chaque équipe.
class _RepechageTab extends ConsumerWidget {
  const _RepechageTab({required this.competitionId});
  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bracket = ref.watch(bracketProvider(competitionId));
    final lives = {
      for (final s in ref.watch(competitionDetailProvider(competitionId)).value?.standings ?? const <CompetitionStandingDto>[])
        if (s.livesLeft != null) s.entityId: s.livesLeft!.toInt(),
    };
    final followed = (ref.watch(followsProvider).value ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    return AsyncView(
      value: bracket,
      errorMessage: "Impossible de charger le repêchage.",
      onRetry: () => ref.invalidate(bracketProvider(competitionId)),
      builder: (value) => _RepechageList(bracket: value, lives: lives, followed: followed),
    );
  }
}

/// Les tours du repêchage. Le match en direct, sinon le prochain (celui d'une équipe suivie d'abord),
/// porte un cadre renforcé et la liste s'y place d'elle-même à l'ouverture ; l'en-tête de chaque tour
/// prend la couleur de son état (rouge en direct, laiton pour le prochain, estompé quand il est fini).
class _RepechageList extends StatefulWidget {
  const _RepechageList({required this.bracket, required this.lives, required this.followed});
  final BracketResponseDto bracket;

  /// Vies restantes par équipe (`standing.livesLeft`, double élimination : 2 au départ).
  final Map<String, int> lives;
  final Set<String> followed;

  @override
  State<_RepechageList> createState() => _RepechageListState();
}

class _RepechageListState extends State<_RepechageList> {
  final _focusKey = GlobalKey();
  bool _scrolled = false;

  /// Une seule fois : un rafraîchissement ne doit pas déplacer la liste sous les doigts.
  void _scrollToFocus() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _focusKey.currentContext;
      if (context != null && context.mounted) Scrollable.ensureVisible(context, alignment: 0.25);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bracket = widget.bracket;
    final lowerNodes = bracket.nodes.where((n) => isLowerBracketName(n.name)).toList();
    if (lowerNodes.isEmpty) return const _EmptyMessage("Pas de repêchage pour cette compétition.");

    final byId = {for (final n in bracket.nodes) n.eventId: n};
    final incomingByTarget = <String, List<BracketLinkDto>>{};
    for (final l in bracket.links) {
      incomingByTarget.putIfAbsent(l.toEventId, () => []).add(l);
    }
    final byRound = <int, List<BracketNodeDto>>{};
    for (final n in lowerNodes) {
      byRound.putIfAbsent(n.round.toInt(), () => []).add(n);
    }
    final rounds = byRound.keys.toList()..sort((a, b) => b.compareTo(a)); // le plus profond = tour 1
    final now = DateTime.now();
    final lowerOnly = bracket.rebuild((b) => b..nodes.where((n) => isLowerBracketName(n.name)));
    final focusId = nextMatchId(lowerOnly, widget.followed);
    final anchorId = anchorMatchId(lowerOnly, widget.followed);
    if (anchorId != null) _scrollToFocus();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const _HowItWorks(),
        for (final (i, round) in rounds.indexed) ...[
          Builder(builder: (context) {
            final (text, color) = _roundState(byRound[round]!, focusId, now);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text("TOUR ${i + 1}$text", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
            );
          }),
          for (final node in byRound[round]!..sort((a, b) => a.name.compareTo(b.name)))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BracketMatchCard(
                key: node.eventId == anchorId ? _focusKey : null,
                node: node,
                sides: matchSides(node, incomingByTarget[node.eventId] ?? const [], byId),
                lives: widget.lives,
                emphasis: node.status == "live" ? CardEmphasis.live : (node.eventId == focusId ? CardEmphasis.next : CardEmphasis.none),
              ),
            ),
        ],
      ],
    );
  }

  /// « · terminé », « · en direct », « · demain à 9 h » : où en est ce tour, et sa couleur.
  static (String, Color) _roundState(List<BracketNodeDto> matches, String? focusId, DateTime now) {
    if (matches.every((m) => m.status == "finished")) return (" · terminé", AppColors.textTertiary);
    if (matches.any((m) => m.status == "live")) return (" · en direct", AppColors.live);
    final dates = matches.where((m) => m.startsAt != null).map((m) => DateTime.parse(m.startsAt!)).toList()..sort();
    final text = dates.isEmpty ? " · à venir" : " · ${scheduleLabel(dates.first, now)}";
    return (text, matches.any((m) => m.eventId == focusId) ? AppColors.brass : AppColors.textSecondary);
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.card), border: Border.all(color: AppColors.surfaceBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("COMMENT ÇA MARCHE", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            "Battu dans le tableau principal ? On rejoue ici. Une défaite de plus et c'est fini. Le vainqueur retrouve le finaliste du haut en grande finale.",
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _BracketMatchCard extends ConsumerWidget {
  const _BracketMatchCard({super.key, required this.node, required this.sides, required this.lives, this.emphasis = CardEmphasis.none});
  final BracketNodeDto node;
  final List<MatchSide> sides;
  final Map<String, int> lives;
  final CardEmphasis emphasis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished = node.status.statusKind == EventStatusKind.finished;
    final hideScores = finished && ref.watch(scoreHiddenProvider(node.eventId));
    final emphasized = emphasis != CardEmphasis.none;
    final accent = emphasis == CardEmphasis.live ? AppColors.live : AppColors.brass;
    return OrnateFrame(
      radius: AppRadii.card,
      enabled: emphasized,
      strong: emphasized,
      color: accent,
      child: Material(
        color: emphasized ? Color.alphaBlend(accent.withValues(alpha: 0.08), AppColors.surface) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openMatch(context, node.eventId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.card), border: emphasized ? null : Border.all(color: AppColors.surfaceBorder)),
            child: Column(
              children: [
                for (final (i, side) in sides.indexed) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.surfaceBorder),
                  _SideRow(side: side, hideScore: hideScores, lives: side.entityId == null || finished ? null : lives[side.entityId]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({required this.side, required this.lives, required this.hideScore});
  final bool hideScore;
  final MatchSide side;

  /// Vies restantes (2 au départ), `null` = pas affiché (équipe inconnue ou match fini).
  final int? lives;

  @override
  Widget build(BuildContext context) {
    final dim = side.lost || side.code == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          BracketTeamLogo(side: side),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              side.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dim ? AppColors.textSecondary : AppColors.textPrimary,
                fontWeight: side.won ? FontWeight.w700 : FontWeight.w500,
                decoration: side.lost ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (lives != null) _Lives(left: lives!),
          if (side.score != null && !hideScore) ...[const SizedBox(width: AppSpacing.sm), Text("${side.score}", style: const TextStyle(fontWeight: FontWeight.w700))],
        ],
      ),
    );
  }
}

/// Deux pastilles : les vies restantes en double élimination (pleines = restantes).
class _Lives extends StatelessWidget {
  const _Lives({required this.left});
  final int left;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: left == 1 ? "1 vie" : "$left vies",
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < left ? AppColors.brass : Colors.transparent,
                border: Border.all(color: i < left ? AppColors.brass : AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}
