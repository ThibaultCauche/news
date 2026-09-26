import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../theme/tokens.dart";
import "../../widgets/event_card.dart";
import "../follows/follows_provider.dart";
import "../next_match/next_match_screen.dart";
import "season_data.dart";

const _tabs = ["Saison", "Tournoi", "Équipes", "Agenda"];

/// Écran 01 (`docs/02`). Seul l'onglet "Saison" est actif au J3 (`docs/04`) ;
/// les autres restent en placeholder, comme la tab bar principale.
class ValorantSeasonScreen extends ConsumerStatefulWidget {
  const ValorantSeasonScreen({super.key});

  @override
  ConsumerState<ValorantSeasonScreen> createState() => _ValorantSeasonScreenState();
}

class _ValorantSeasonScreenState extends ConsumerState<ValorantSeasonScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(valorantSeasonProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Valorant"), actions: [_FollowSeasonPill(competitionId: overview.value?.rootCompetitionId)]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: Text("E-sport · saison VCT 2026", style: TextStyle(color: AppColors.textSecondary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _SeasonTabs(selectedIndex: _tabIndex, onSelected: (i) => setState(() => _tabIndex = i)),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _tabIndex != 0
                ? const Center(child: Text("Bientôt disponible", style: TextStyle(color: AppColors.textSecondary)))
                : switch (overview) {
                    AsyncData(:final value) => value == null
                        ? const Center(child: Text("Aucune compétition Valorant en cours.", style: TextStyle(color: AppColors.textSecondary)))
                        : _SeasonBody(overview: value),
                    AsyncError() => const Center(child: Text("Impossible de charger la saison.")),
                    _ => const Center(child: CircularProgressIndicator()),
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
  const _SeasonTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          for (final (i, label) in _tabs.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: AppMotion.microDuration,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? AppColors.textPrimary : Colors.transparent,
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
              ),
            ),
        ],
      ),
    );
  }
}

/// Suit la ligue racine (ex. "VCT") plutôt qu'une seule étape (docs/04 J4) :
/// couvre toutes les compétitions filles (abonnement hiérarchique, docs/03 §6).
class _FollowSeasonPill extends ConsumerWidget {
  const _FollowSeasonPill({required this.competitionId});

  final String? competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = competitionId;
    if (id == null) return const SizedBox.shrink();
    final following = isFollowing(ref.watch(followsProvider).value, FollowTargetType.competition, id);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: GestureDetector(
        onTap: () => following
            ? ref.read(followsControllerProvider).unfollow(FollowTargetType.competition, id)
            : ref.read(followsControllerProvider).follow(FollowTargetType.competition, id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            color: following ? AppColors.gold.withValues(alpha: 0.15) : AppColors.textPrimary,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: following ? Border.all(color: AppColors.gold) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (following) const Icon(Icons.check_rounded, size: 14, color: AppColors.gold),
              if (following) const SizedBox(width: 4),
              Text(
                following ? "Suivi" : "Suivre",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: following ? AppColors.gold : AppColors.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonBody extends StatelessWidget {
  const _SeasonBody({required this.overview});

  final SeasonOverview overview;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
      children: [
        _SeasonCard(overview: overview),
        const SizedBox(height: AppSpacing.md),
        _NowCard(overview: overview),
        if (overview.playedSteps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text("DÉJÀ JOUÉ", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          Card(
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
    return Card(
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
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final step in widget.overview.steps) ...[
            _StepDot(step: step, isCurrent: step.id == widget.overview.currentStep.id),
            if (step != widget.overview.steps.last) Container(width: 14, height: 1, color: AppColors.surfaceBorder),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step, required this.isCurrent});

  final SeasonStep step;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final hasEnded = (step.endsAt ?? step.startsAt)?.isBefore(DateTime.now()) ?? false;
    final done = hasEnded && !isCurrent;
    final color = isCurrent ? AppColors.live : (done ? AppColors.textSecondary : AppColors.textTertiary);
    return Column(
      children: [
        SizedBox(
          height: 16,
          child: isCurrent
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("ICI", maxLines: 1, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 2),
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.live : (done ? color : Colors.transparent),
            shape: step.isMasters ? BoxShape.rectangle : BoxShape.circle,
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 46,
          child: Text(
            step.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.overview});

  final SeasonOverview overview;

  @override
  Widget build(BuildContext context) {
    final step = overview.currentStep;
    // Le statut de la compétition (`step.status`) n'est pas toujours tenu à
    // jour côté source ; on se fie plutôt aux matchs réellement en direct.
    final isLive = step.status == "live" || overview.currentMatches.any((e) => e.status == "live");
    return Card(
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
            Text(step.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (overview.currentMatches.isEmpty)
              const Text("Aucun match programmé pour l'instant.", style: TextStyle(color: AppColors.textSecondary))
            else
              for (final event in overview.currentMatches.take(5))
                EventCard(
                  event: event,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: event.id))),
                ),
          ],
        ),
      ),
    );
  }
}
