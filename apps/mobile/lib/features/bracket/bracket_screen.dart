import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/iterable_x.dart";
import "../../domain/event_status.dart";
import "../../theme/tokens.dart";
import "../../widgets/group_bracket_tree.dart";
import "../follows/follows_provider.dart";
import "bracket_painter.dart";
import "bracket_provider.dart";

bool _isLowerBracket(String name) => name.toLowerCase().contains("lower bracket");

/// Nœuds dont un participant est suivi : le « chemin en or » de l'arbre
/// radial (écran 02/07, règle 12 de `CLAUDE.md`). Fonction pure, testée
/// indépendamment du widget (`bracket_logic_test.dart`).
Set<String> highlightedEventIds(List<BracketNodeDto> nodes, Set<String> followedEntityIds) {
  return nodes.where((n) => n.participants.any((p) => followedEntityIds.contains(p.entityId))).map((n) => n.eventId).toSet();
}

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
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(competitionDetailProvider(widget.competitionId));

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: const Text("Valorant", style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      body: switch (detail) {
        AsyncData(:final value) => _BracketBody(
            title: widget.title,
            subtitle: widget.subtitle,
            children: value.children.toList(),
            tabIndex: _tabIndex,
            onTabSelected: (i) => setState(() => _tabIndex = i),
          ),
        AsyncError() => const Center(child: Text("Impossible de charger cette compétition.")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _BracketBody extends ConsumerWidget {
  const _BracketBody({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.tabIndex,
    required this.onTabSelected,
  });

  final String title;
  final String subtitle;
  final List<CompetitionChildDto> children;
  final int tabIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupIds = groupCompetitionIds(children);
    final playoffs = children.firstWhereOrNull((c) => c.name.toLowerCase().contains("playoff"));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _BracketTabs(selectedIndex: tabIndex, onSelected: onTabSelected),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: switch (tabIndex) {
            0 => _GroupsTab(groupIds: groupIds),
            1 => playoffs == null
                ? const _EmptyMessage("Phase finale pas encore commencée.")
                : _FinalsTab(competitionId: playoffs.id),
            _ => playoffs == null
                ? const _EmptyMessage("Repêchage pas encore commencé.")
                : _RepechageTab(competitionId: playoffs.id),
          },
        ),
      ],
    );
  }
}

class _BracketTabs extends StatelessWidget {
  const _BracketTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const _labels = ["Groupes", "Phase finale", "Repêchage"];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
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
                      _labels[i],
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
  Widget build(BuildContext context) => Center(child: Text(text, style: const TextStyle(color: AppColors.textSecondary)));
}

/// Écran 06 : l'arbre de qualification de chaque poule (Ouverture →
/// Vainqueurs/Élimination → Decider → Qualifiés), pas juste un classement —
/// même widget que la carte "Maintenant" de l'écran Saison (`GroupBracketTree`).
class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.groupIds});
  final List<String> groupIds;

  @override
  Widget build(BuildContext context) {
    if (groupIds.isEmpty) return const _EmptyMessage("Pas de phase de groupes pour cette compétition.");
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [for (final id in groupIds) GroupBracketTree(competitionId: id)],
    );
  }
}

/// Écran 02/07 : arbre radial du tableau haut + finale (le tableau bas vit
/// dans l'onglet Repêchage).
class _FinalsTab extends ConsumerWidget {
  const _FinalsTab({required this.competitionId});
  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bracket = ref.watch(bracketProvider(competitionId));
    final follows = ref.watch(followsProvider).value;

    return switch (bracket) {
      AsyncData(:final value) => _RadialTree(bracket: value, follows: follows),
      AsyncError() => const _EmptyMessage("Impossible de charger l'arbre."),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _RadialTree extends StatelessWidget {
  const _RadialTree({required this.bracket, required this.follows});
  final BracketResponseDto bracket;
  final List<FollowStateDto>? follows;

  @override
  Widget build(BuildContext context) {
    final upperNodes = bracket.nodes.where((n) => !_isLowerBracket(n.name)).toList();
    final upperEventIds = upperNodes.map((n) => n.eventId).toSet();
    final upperLinks = bracket.links.where((l) => upperEventIds.contains(l.fromEventId) && upperEventIds.contains(l.toEventId)).toList();

    final followedEntityIds = (follows ?? const []).where((f) => f.targetType == "entity").map((f) => f.targetId).toSet();
    final highlighted = highlightedEventIds(upperNodes, followedEntityIds);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            // Carré plutôt que `Size.infinite` : un cercle a besoin d'un
            // repère de taille unique, sans quoi les anneaux débordent du
            // côté le plus court (l'écran est bien plus haut que large).
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: BracketPainter(nodes: upperNodes, links: upperLinks, highlightedEventIds: highlighted),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md),
          child: Text("En or, le chemin suivi. En rouge, le match en direct.", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      ],
    );
  }
}

/// Écran 05 : tours du repêchage, "perdant de …" tant que le match précédent
/// n'est pas terminé.
class _RepechageTab extends ConsumerWidget {
  const _RepechageTab({required this.competitionId});
  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bracket = ref.watch(bracketProvider(competitionId));
    return switch (bracket) {
      AsyncData(:final value) => _RepechageList(bracket: value),
      AsyncError() => const _EmptyMessage("Impossible de charger le repêchage."),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _RepechageList extends StatelessWidget {
  const _RepechageList({required this.bracket});
  final BracketResponseDto bracket;

  @override
  Widget build(BuildContext context) {
    final lowerNodes = bracket.nodes.where((n) => _isLowerBracket(n.name)).toList();
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

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        for (final round in rounds) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text("TOUR ${rounds.indexOf(round) + 1}", style: Theme.of(context).textTheme.labelSmall),
          ),
          for (final node in byRound[round]!)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BracketMatchCard(node: node, incoming: incomingByTarget[node.eventId] ?? const [], byId: byId),
            ),
        ],
      ],
    );
  }
}

class _BracketMatchCard extends StatelessWidget {
  const _BracketMatchCard({required this.node, required this.incoming, required this.byId});
  final BracketNodeDto node;
  final List<BracketLinkDto> incoming;
  final Map<String, BracketNodeDto> byId;

  @override
  Widget build(BuildContext context) {
    final rows = bracketMatchRows(node, incoming, byId);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: node.status.statusKind == EventStatusKind.live ? AppColors.live : AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, score, isWinner) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isWinner ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isWinner ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (score != null) Text(score, style: const TextStyle(color: AppColors.textPrimary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
