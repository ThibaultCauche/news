import "../../widgets/ornate_frame.dart";
import "../forum/forum_entry.dart";
import "../forum/forum_providers.dart";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/settings_provider.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/event_card.dart";
import "../../widgets/game_logo.dart";
import "../../widgets/group_bracket_tree.dart";
import "../bracket/bracket_provider.dart";
import "../bracket/bracket_screen.dart";
import "../bracket/kickoff_lives_screen.dart";
import "../learn/learn_screen.dart";
import "../next_match/next_match_screen.dart";
import "../agenda/agenda_screen.dart";
import "../team/team_screen.dart";
import "../valorant_season/season_data.dart";
import "competitions_data.dart";
import "leagues_tab.dart";

const _tabs = ["Compétitions", "Ligues", "Équipes", "Agenda"];
// Tutos écrits seulement pour Valorant pour l'instant (J12) : l'onglet n'apparaît pas ailleurs.
const _learnGames = {"valorant"};

/// Kickoff se raconte en « 3 vies » (écran 14), les autres étapes à élimination
/// double en arbre radial + groupes + repêchage (écrans 02/05/06/07) — `docs/02`.
void openCompetitionPage(BuildContext context, {required String id, required String name, String? status}) {
  final subtitle = status?.statusKind.label ?? "";
  if (name.toLowerCase().contains("kickoff")) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KickoffLivesScreen(competitionId: id, title: name, subtitle: subtitle),
      ),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BracketScreen(competitionId: id, title: name, subtitle: subtitle),
    ),
  );
}

void _openStep(BuildContext context, SeasonStep step) => openCompetitionPage(context, id: step.id, name: step.name, status: step.status);

/// Page jeu (écran 01 de `docs/02`, J9) : Compétitions (frise de saison,
/// en cours, déjà jouées), Ligues (J10), Équipes et Agenda, ces deux derniers filtrés sur le
/// jeu. `game` vient du catalogue : rien de propre à Valorant dans l'écran, sauf
/// `valorantSeasonProvider` (seul jeu ingéré pour l'instant).
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.game});

  final CatalogGameDto game;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(valorantSeasonProvider);
    final scoresHidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final game = widget.game;
    final hasLearn = _learnGames.contains(game.slug);
    final forumEnabled = ref.watch(forumEnabledProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameLogo(slug: game.slug, size: 30),
            const SizedBox(width: AppSpacing.sm),
            Text(game.name),
          ],
        ),
        actions: [
          if (hasLearn) const LearnHelpButton(articleId: "le-jeu"),
          _FavoriteGameButton(game: game.slug),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: Text("E-sport", style: TextStyle(color: AppColors.textSecondary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _SeasonTabs(
              labels: [..._tabs, if (forumEnabled) "Discussions", if (hasLearn) "Apprendre"],
              selectedIndex: _tabIndex,
              onSelected: (i) => setState(() => _tabIndex = i),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (_tabIndex) {
              1 => LeaguesTab(game: game),
              2 => _TeamsTab(game: game),
              3 => AgendaScreen(leagueIds: [for (final l in game.leagues) l.id]),
              4 when forumEnabled => ForumThreadsTab(game: game.slug, gameName: game.name),
              4 || 5 => LearnTab(game: game.slug),
              _ => AsyncView(
                value: overview,
                errorMessage: "Impossible de charger la saison.",
                onRetry: () => ref.invalidate(valorantSeasonProvider),
                builder: (value) => value == null
                    ? Center(
                        child: Text("Aucune compétition ${game.name} en cours.", style: const TextStyle(color: AppColors.textSecondary)),
                      )
                    : _SeasonBody(overview: value, scoresHidden: scoresHidden),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Capsule compacte façon iOS plutôt que le `SegmentedButton` Material (trop
/// haut, et son texte passe à la ligne sur un onglet comme "Saison" dès que
/// la police système est agrandie). `FittedBox` réduit le texte au lieu de
/// le couper, pour rester correct avec les réglages d'accessibilité.
class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({required this.labels, required this.selectedIndex, required this.onSelected});

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  // Au-delà de cinq onglets (Discussions, Apprendre…), le texte ne tient plus : la capsule défile.
  static const _maxFixed = 5;

  Widget _tab(int i, String label, {required bool fixed}) {
    return GestureDetector(
      onTap: () => onSelected(i),
      child: AnimatedContainer(
        duration: AppMotion.microDuration,
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: fixed ? 6 : AppSpacing.md),
        decoration: BoxDecoration(
          color: i == selectedIndex ? AppColors.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: i == selectedIndex ? AppColors.background : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixed = labels.length <= _maxFixed;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.brass.withValues(alpha: 0.4), width: 0.8),
      ),
      child: fixed
          ? Row(children: [for (final (i, label) in labels.indexed) Expanded(child: _tab(i, label, fixed: true))])
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final (i, label) in labels.indexed) _tab(i, label, fixed: false)])),
    );
  }
}

/// Étoile « Favori » : raccourci vers le jeu depuis l'onglet Compétitions, sans
/// abonnement ni notification (vocabulaire « Suivre » réservé aux compétitions,
/// équipes et matchs).
class _FavoriteGameButton extends ConsumerWidget {
  const _FavoriteGameButton({required this.game});

  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(favoriteGamesProvider).value?.contains(game) ?? false;
    return IconButton(
      tooltip: favorite ? "Retirer des favoris" : "Ajouter aux favoris",
      onPressed: () => runOrShowError(context, () => ref.read(favoriteGamesProvider.notifier).toggle(game)),
      icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: favorite ? AppColors.gold : AppColors.textSecondary),
    );
  }
}

/// Équipes du jeu, triées par nom ; l'appui ouvre la fiche équipe (écran 10).
class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.game});

  final CatalogGameDto game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(gameTeamsProvider(game.slug)),
      errorMessage: "Impossible de charger les équipes.",
      onRetry: () => ref.invalidate(gameTeamsProvider(game.slug)),
      builder: (value) => value.isEmpty
          ? const Center(
              child: Text("Aucune équipe pour l'instant.", style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
              children: [
                for (final team in value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _TeamLogo(team: team),
                    title: Text(team.name),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TeamScreen(entityId: team.id, breadcrumb: game.name),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.team});

  final EntityListItemDto team;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        (team.shortName ?? team.name).characters.take(3).toString().toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
      ),
    );
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.chip)),
      clipBehavior: Clip.antiAlias,
      child: team.imageUrl == null ? fallback : Image.network(team.imageUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class _SeasonBody extends StatelessWidget {
  const _SeasonBody({required this.overview, required this.scoresHidden});

  final SeasonOverview overview;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      children: [
        _SeasonCard(overview: overview),
        const SizedBox(height: AppSpacing.md),
        _NowCard(overview: overview, scoresHidden: scoresHidden),
        if (overview.playedSteps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text("DÉJÀ JOUÉ", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          FramedCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (final step in overview.playedSteps)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(step.name),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                      onTap: () => _openStep(context, step),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.overview});

  final SeasonOverview overview;

  @override
  Widget build(BuildContext context) {
    return FramedCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("SAISON 2026", style: Theme.of(context).textTheme.labelSmall),
                Text("${(overview.progress * 100).round()} %", style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SeasonTimeline(overview: overview),
            const SizedBox(height: AppSpacing.sm),
            Text(_caption(overview), style: const TextStyle(color: AppColors.textSecondary)),
            // Contexte Liquipedia : change avec l'étape en cours (J6), donc
            // déjà dynamique — mais son texte plein débordait la carte.
            // Tronqué à 2 lignes ; l'attribution reste (règle 8 de
            // CLAUDE.md, non négociable dès qu'on affiche du Liquipedia).
            if (overview.liquipediaContext != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                overview.liquipediaContext!.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Source : ${overview.liquipediaContext!.source_} (${overview.liquipediaContext!.license})",
                style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Phrase déterministe à partir de la position de l'étape en cours, jamais
  // de texte libre (même principe que la neutralité politique, règle 9).
  String _caption(SeasonOverview overview) {
    final isLast = overview.currentStep.id == overview.steps.last.id;
    if (isLast) return "Dernière ligne droite : il ne reste que ${overview.currentStep.name}.";
    final remaining = overview.steps.length - overview.steps.indexWhere((s) => s.id == overview.currentStep.id) - 1;
    return "Prochaine étape : ${overview.currentStep.name} · $remaining étape${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}.";
  }
}

/// Se remplit une seule fois par jour ; ensuite l'écran est vu sans
/// ré-animer (`docs/maquettes/motion-specs` — "Mouvement · 01 Saison").
/// Recentre automatiquement sur l'étape en cours : avec les 9 étapes réelles
/// de la saison 2026 (contre 6 dans la maquette, fictives), la frise déborde
/// toujours de l'écran, donc "ICI" doit s'afficher sans geste de l'utilisateur.
class _SeasonTimeline extends StatefulWidget {
  const _SeasonTimeline({required this.overview});

  final SeasonOverview overview;

  @override
  State<_SeasonTimeline> createState() => _SeasonTimelineState();
}

// Largeur approximative d'une étape (étiquette de 46 px + trait de 14 px) :
// sert uniquement à estimer le décalage de défilement initial, pas à
// positionner les points eux-mêmes (rendus par `Row`/`Column` normaux).
const _stepPitch = 60.0;

class _SeasonTimelineState extends State<_SeasonTimeline> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final index = widget.overview.steps.indexWhere((s) => s.id == widget.overview.currentStep.id);
      if (index < 0) return;
      final viewport = _scrollController.position.viewportDimension;
      final target = (index + 0.5) * _stepPitch - viewport / 2;
      _scrollController.jumpTo(target.clamp(0, _scrollController.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.overview.steps;
    final currentIndex = steps.indexWhere((s) => s.id == widget.overview.currentStep.id);
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, step) in steps.indexed) ...[
            _StepDot(step: step, isCurrent: i == currentIndex, bright: i <= currentIndex),
            // Plein et clair jusqu'à l'étape en cours (comme la maquette : un
            // seul trait continu de Kickoff à Champions, pas une brillance
            // par étape passée), pointillé seulement pour le dernier segment,
            // décoratif, vers `_PauseDot`.
            _Connector(dashed: i == steps.length - 1, bright: i <= currentIndex),
          ],
          // Point de fin décoratif, hors de nos données (aucune saison future
          // chargée) : signale juste "rien de programmé après", pas une vraie
          // étape — creux, pointillé, jamais cliquable.
          const _PauseDot(),
        ],
      ),
    );
  }
}

// Distance entre le haut de chaque colonne (`_StepDot`/`_PauseDot`) et le
// centre du point : pastille "ICI" (18) + espace (4) + demi-point (12).
// Partagée avec `_Connector` pour que le trait tombe pile au milieu des
// points quel que soit le contenu en dessous (l'étiquette n'a pas la même
// hauteur pour tout le monde, donc le bas de colonne ne s'y prête pas).
const _dotCenterY = 18.0 + 4.0 + 12.0;

/// Trait entre deux points, centré verticalement sur les points eux-mêmes
/// (`docs/maquettes/svg/01-valorant-saison.svg` : une seule ligne continue à
/// hauteur des points, pas des segments alignés en haut de ligne — c'était le
/// bug signalé, le trait flottait au-dessus des points). Le segment
/// décoratif (pointillé, vers `_PauseDot`) reste toujours terne, même s'il
/// suit l'étape en cours.
class _Connector extends StatelessWidget {
  const _Connector({required this.dashed, required this.bright});

  final bool dashed;
  final bool bright;

  static Color colorFor({required bool bright}) => Colors.white.withValues(alpha: bright ? 0.45 : 0.18);

  @override
  Widget build(BuildContext context) {
    final color = colorFor(bright: bright && !dashed);
    final line = dashed
        ? Row(
            children: [
              for (var i = 0; i < 3; i++) ...[Container(width: 2, height: 2, color: color), if (i != 2) const SizedBox(width: 2)],
            ],
          )
        : Container(width: 14, height: 2, color: color);
    return Padding(
      padding: const EdgeInsets.only(top: _dotCenterY - 1),
      child: line,
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step, required this.isCurrent, required this.bright});

  final SeasonStep step;
  final bool isCurrent;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final hasEnded = (step.endsAt ?? step.startsAt)?.isBefore(DateTime.now()) ?? false;
    final done = hasEnded && !isCurrent;
    // `AppColors.textSecondary`/`textTertiary` portent leur propre alpha (55 %
    // / 30 %) — correct pour du texte, mais ça rendait les points "déjà joué"
    // translucides au lieu de pleins. `textPrimary` est le seul token
    // entièrement opaque (`docs/02` — pas de couleur en dur en dehors de
    // `tokens.dart`, règle 12).
    final color = isCurrent ? AppColors.live : (done ? AppColors.textPrimary : AppColors.textTertiary);
    Widget dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.live : (done ? color : Colors.transparent),
        shape: step.isMasters ? BoxShape.rectangle : BoxShape.circle,
        border: Border.all(color: color),
      ),
    );
    // Losange plutôt que carré pour une étape majeure (Masters) : le tourner
    // demande son propre `SizedBox`, sinon la rotation déborde sur le trait
    // voisin (même défaut que le losange non tourné qu'il remplace).
    if (step.isMasters) dot = Transform.rotate(angle: math.pi / 4, child: dot);
    // Le point en cours grossit dans un halo rouge translucide, avec un point
    // plein cerclé de blanc au centre (`docs/maquettes/svg/01-valorant-saison.svg` :
    // pas un simple cercle bordé de rouge, contrairement à `widgets/season_timeline.dart`).
    if (isCurrent) {
      dot = Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: AppColors.live,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
        ),
      );
      dot = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.live.withValues(alpha: 0.22), shape: BoxShape.circle),
        child: dot,
      );
    }
    return GestureDetector(
      onTap: () => _openStep(context, step),
      // Largeur forcée à 46 comme les autres colonnes, quoi qu'il arrive :
      // sans ça, la pastille "· ICI" (plus large que 46 dès que le nom de
      // l'étape est long) élargissait TOUTE la colonne, décentrait son point
      // par rapport aux voisins, et cassait le trait continu qui suppose un
      // écart constant entre points (`_Connector`, largeur fixe) — c'était le
      // trait "en pointillés séparés" signalé. `OverflowBox` laisse la
      // pastille déborder visuellement sans influencer cette largeur.
      child: SizedBox(
        width: 46,
        child: Stack(
          children: [
            // Bout de trait sur toute la largeur de la colonne (46, pas 24) :
            // le point n'occupe que 24 px en son centre, avec ~11 px de marge
            // de chaque côté (pour laisser de la place au nom en dessous) —
            // un trait limité à ces 24 px s'arrêtait avant le bord de la
            // colonne, laissant deux trous invisibles de 11 px de chaque
            // côté avant que `_Connector` (qui part pile du bord de colonne)
            // ne prenne le relais. C'était la vraie raison des trous
            // signalés (pas une marge/un padding entre widgets, un trait
            // trop court).
            Positioned(
              top: _dotCenterY - 1,
              left: 0,
              width: 46,
              height: 2,
              child: Container(color: _Connector.colorFor(bright: bright)),
            ),
            Column(
              children: [
                SizedBox(
                  height: 18,
                  child: isCurrent
                      ? OverflowBox(
                          maxWidth: 200,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(AppRadii.chip)),
                            child: Text(
                              step.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                SizedBox(width: 24, height: 24, child: Center(child: dot)),
                const SizedBox(height: 4),
                // Le nom vit dans la pastille "· ICI" pour l'étape en cours
                // (comme la maquette) : pas de doublon en dessous. Largeur
                // fixe à 46 (comme la colonne) plutôt qu'un débordement : un
                // nom réel ("EMEA Stage 1 2026"…) tient sur 3-4 lignes
                // étroites sans recouvrir ses voisins — plus haut que large,
                // comme demandé.
                if (!isCurrent)
                  Text(
                    step.name,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Point de fin décoratif de la frise (`docs/maquettes/01-valorant-saison.png`) :
/// creux et pointillé pour se distinguer d'une vraie étape (même logique
/// visuelle que les placeholders "TBD" ailleurs dans l'appli) — jamais
/// cliquable, il ne correspond à aucune compétition.
class _PauseDot extends StatelessWidget {
  const _PauseDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Stack(
        children: [
          // Même logique que `_StepDot` : le trait couvre toute la colonne
          // (46), pas seulement la case du point (24), sinon le segment
          // pointillé qui précède s'arrête avant de le toucher.
          Positioned(
            top: _dotCenterY - 1,
            left: 0,
            width: 46,
            height: 2,
            child: Container(color: _Connector.colorFor(bright: false)),
          ),
          Column(
            children: [
              const SizedBox(height: 18),
              const SizedBox(height: 4),
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  // Rempli de la couleur de la carte (pas transparent) :
                  // sinon le trait juste en dessous se voit à travers
                  // l'anneau creux, au lieu du "trou" propre de la maquette.
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.textTertiary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "À venir",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NowCard extends ConsumerWidget {
  const _NowCard({required this.overview, required this.scoresHidden});

  final SeasonOverview overview;
  final bool scoresHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = overview.currentStep;
    // Le statut de la compétition (`step.status`) n'est pas toujours tenu à
    // jour côté source ; on se fie plutôt aux matchs réellement en direct.
    final isLive = step.status == "live" || overview.currentMatches.any((e) => e.status == "live");
    // Poules GSL (ex. Champions 2026) : l'arbre de qualification remplace la
    // liste de tuiles de match, déjà présente dans l'agenda et sans lien
    // entre les matchs (règle 3 — même modèle générique compétition/événement,
    // pas de champ "a des poules" : on le retrouve par nom, comme
    // `groupCompetitionIds` dans `bracket_provider.dart`). Une étape sans
    // poules (Kickoff, Playoffs) garde la liste de tuiles.
    final children = ref.watch(competitionDetailProvider(step.id)).value?.children;
    final groupIds = groupCompetitionIds(children?.toList() ?? const []);

    return FramedCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLive ? "MAINTENANT" : "PROCHAINE ÉTAPE",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isLive ? AppColors.live : null),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(child: Text(step.name, style: Theme.of(context).textTheme.titleLarge)),
                TextButton(onPressed: () => _openStep(context, step), child: const Text("Voir le tableau")),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (groupIds.isNotEmpty)
              for (final id in groupIds) GroupBracketTree(competitionId: id)
            else if (overview.currentMatches.isEmpty)
              const Text("Aucun match programmé pour l'instant.", style: TextStyle(color: AppColors.textSecondary))
            else
              for (final event in overview.currentMatches.take(5))
                EventCard(
                  event: event,
                  scoresHidden: scoresHidden,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
                ),
          ],
        ),
      ),
    );
  }
}
