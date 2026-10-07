import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/settings_provider.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/bracket_match_card.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/section_label.dart";
import "../../widgets/segmented_control.dart";
import "../account/account_gate.dart";
import "../discussion/share_sheet.dart";
import "../profile/community_providers.dart";
import "bracket_model.dart";
import "pickem_model.dart";

/// Pick'em d'un tableau (`GET /v1/competitions/:id/pickem`, J25) : le vainqueur de chaque match, à choisir avant le
/// premier match. Le serveur décide du verrouillage et de ce que les autres peuvent voir.
final pickemProvider = FutureProvider.autoDispose.family<PickemDto?, String>((ref, competitionId) async {
  // Invité : pas de pick'em (il faut un compte, comme pour les pronostics de match).
  if (!ref.watch(signedInProvider)) return null;
  try {
    return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetPickem(id: competitionId)).data;
  } on DioException catch (e) {
    // 404 : cette étape n'a pas de tableau à pronostiquer (poule, phase suisse).
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

final pickemGroupsProvider = FutureProvider.autoDispose.family<PickemGroupsDto?, String>((ref, competitionId) async {
  if (!ref.watch(signedInProvider)) return null;
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetPickemGroups(id: competitionId)).data;
});

final myPickemsProvider = FutureProvider.autoDispose<List<MyPickemDto>>((ref) async {
  if (!ref.watch(signedInProvider)) return const [];
  return (await ref.watch(apiClientProvider).getCommunityApi().communityControllerMyPickems()).data?.toList() ?? const [];
});

class PickemController {
  PickemController(this._ref);

  final Ref _ref;

  /// Enregistre le tableau ; `false` si la personne a renoncé à se connecter.
  Future<bool> save(String competitionId, Map<String, String> picks) async {
    if (!await ensureAccount(_ref)) return false;
    await _ref.read(apiClientProvider).getCommunityApi().communityControllerPutPickem(
          id: competitionId,
          putPickemDto: PutPickemDto(
            (b) => b..picks.replace([for (final e in picks.entries) PickemChoiceInputDto((c) => c..eventId = e.key..pickedEntityId = e.value)]),
          ),
        );
    _ref.invalidate(pickemProvider(competitionId));
    _ref.invalidate(pickemGroupsProvider(competitionId));
    _ref.invalidate(myPickemsProvider);
    return true;
  }
}

final pickemControllerProvider = Provider((ref) => PickemController(ref));

void _openPickem(BuildContext context, WidgetRef ref, String competitionId) {
  // Le tournoi a pu commencer depuis la dernière lecture : on relit avant d'ouvrir.
  ref.invalidate(pickemProvider(competitionId));
  ref.invalidate(pickemGroupsProvider(competitionId));
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PickemScreen(competitionId: competitionId)));
}

/// Ouvre le pick'em d'une compétition depuis une notification (rappel avant le début).
void openPickemScreen(BuildContext context, String competitionId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PickemScreen(competitionId: competitionId)));

/// Carte d'entrée au-dessus de l'arbre de la phase finale : invitation à remplir le tableau avant le début, puis
/// résumé, puis (tableau verrouillé) invitation à pronostiquer les prochains matchs. Rien quand l'étape n'a pas de pick'em.
class PickemCard extends ConsumerWidget {
  const PickemCard({super.key, required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickem = ref.watch(pickemProvider(competitionId)).value;
    if (pickem == null || !pickem.open) return const SizedBox.shrink();
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final over = pickem.matches.every((m) => m.winnerEntityId != null);
    // Tableau fermé et aucun choix : la carte n'a de sens que s'il reste un match à pronostiquer.
    final upcoming = pickem.matches.any((m) => m.status == "scheduled" && m.participants.length >= 2 && m.winnerEntityId == null);
    if (pickem.locked && pickem.picks.isEmpty && !upcoming) return const SizedBox.shrink();
    final text = !pickem.locked
        ? (pickem.picks.isEmpty ? "Choisis le vainqueur de chaque match avant le début." : "${pickem.picks.length}/${pickem.matches.length} matchs choisis. Tu peux changer jusqu'au début.")
        : pickem.picks.isEmpty
            ? "Le tableau est verrouillé. Pronostique les prochains matchs."
            : hidden
                ? "Ton tableau est verrouillé. Résultats masqués (sans spoil)."
                : over
                    ? "${pickem.points} point${pickem.points > 1 ? "s" : ""} au total."
                    : "${pickem.points} point${pickem.points > 1 ? "s" : ""}, encore jusqu'à ${pickem.maxRemaining} possibles.";
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: FramedCard(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => _openPickem(context, ref, competitionId),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel("PICK'EM"),
                      const SizedBox(height: 2),
                      Text(text, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.brass),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section « Mes pick'em » de l'écran Pronostics : les tableaux où j'ai fait au moins un choix.
class MyPickemsSection extends ConsumerWidget {
  const MyPickemsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myPickemsProvider).value ?? const <MyPickemDto>[];
    if (mine.isEmpty) return const SizedBox.shrink();
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("MES PICK'EM"),
        const SizedBox(height: AppSpacing.sm),
        for (final p in mine)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FramedCard(
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(p.locked ? "Verrouillé" : "${p.picked}/${p.total} matchs choisis", style: const TextStyle(color: AppColors.textSecondary)),
                trailing: p.locked && !hidden ? Text("${p.points} pts", style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w700)) : const Icon(Icons.chevron_right_rounded),
                onTap: () => _openPickem(context, ref, p.competitionId),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class PickemScreen extends ConsumerStatefulWidget {
  const PickemScreen({super.key, required this.competitionId});

  final String competitionId;

  @override
  ConsumerState<PickemScreen> createState() => _PickemScreenState();
}

class _PickemScreenState extends ConsumerState<PickemScreen> {
  // Le tableau en cours de saisie ; `null` tant qu'on n'a pas touché (on montre alors celui du serveur).
  Map<String, String>? _draft;
  bool _saving = false;
  // 0 = liste, 1 = colonnes.
  int _view = 0;

  Map<String, String> _saved(PickemDto p) => {for (final c in p.picks) c.eventId: c.pickedEntityId};

  List<PickemNode> _nodes(PickemDto p) => [
        for (final m in p.matches) (id: m.eventId, participants: m.participants.toList(), feeders: [for (final f in m.feeders) (fromId: f.fromEventId, winner: f.outcome == PickemFeederDtoOutcomeEnum.winner)]),
      ];

  Future<void> _save(PickemDto p) async {
    final draft = _draft;
    if (_saving || draft == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(pickemControllerProvider).save(widget.competitionId, draft);
      if (saved && mounted) setState(() => _draft = null);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseChampion(PickemDto p, Map<String, String> picks, List<PickemNode> nodes) async {
    final teams = {for (final t in p.teams) t.entityId: t};
    final starters = {for (final n in nodes) if (n.feeders.isEmpty) ...n.participants}.where(teams.containsKey).toList();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
                child: Text("Qui va gagner le tournoi ?", style: Theme.of(context).textTheme.titleLarge),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: Text("Ton champion gagne tous ses matchs ; tu complètes le reste ensuite. +3 points si c'est le bon.", style: TextStyle(color: AppColors.textSecondary)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in starters)
                      ListTile(
                        leading: BracketTeamLogo(side: (label: teams[id]!.name, code: teams[id]!.shortName, imageUrl: teams[id]!.imageUrl, entityId: id, score: null, won: false, lost: false)),
                        title: Text(teams[id]!.name),
                        onTap: () => Navigator.of(context).pop(id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _draft = prunePickem(nodes, {...picks, ...championPath(nodes, chosen)}));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(pickemProvider(widget.competitionId));
    final canShare = value.value?.picks.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(actions: [if (canShare) ShareButton(kind: ShareDtoKindEnum.pickem, refId: widget.competitionId)]),
      body: SafeArea(
        child: AsyncView<PickemDto?>(
          value: value,
          errorMessage: "Impossible de charger le pick'em.",
          onRetry: () => ref.invalidate(pickemProvider(widget.competitionId)),
          builder: (p) {
            if (p == null) return const Center(child: Text("Pas de pick'em pour cette étape.", style: TextStyle(color: AppColors.textSecondary)));
            return _body(context, p);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PickemDto p) {
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final picks = _draft ?? _saved(p);
    final nodes = _nodes(p);
    final candidates = pickemCandidates(nodes, picks);
    final teams = {for (final t in p.teams) t.entityId: t};
    final editable = !p.locked;
    final dirty = _draft != null;
    final groups = ref.watch(pickemGroupsProvider(widget.competitionId)).value;
    final aliveById = {for (final c in p.picks) c.eventId: c.alive};
    final settledAll = p.matches.every((m) => m.winnerEntityId != null);

    // Ce que dit le serveur des autres : vote de chaque groupe par match (vide avant le verrouillage).
    List<_GroupVote> votesFor(String eventId) => [
          if (groups != null && groups.locked)
            for (final g in groups.groups)
              if (g.groupPicks.where((c) => c.eventId == eventId).firstOrNull case final c?)
                (group: g.name, team: teams[c.pickedEntityId]?.shortName ?? teams[c.pickedEntityId]?.name ?? "?", right: c.points == null ? null : c.points! > 0),
        ];

    final status = editable
        ? "Touche l'équipe qui va gagner chaque match. Plus on approche de la finale, plus le match rapporte (de 1 à 4 points), +5 points si tout est juste, +3 si ton champion gagne."
        : hidden
            ? "Le tableau est verrouillé. Les résultats sont masqués (sans spoil)."
            : settledAll
                ? "Tournoi terminé : ${p.points} point${p.points > 1 ? "s" : ""}${p.bonus != null ? ", dont ${p.bonus} pour le tableau parfait" : ""}${p.championBonus != null ? ", dont ${p.championBonus} pour le champion" : ""}."
                : "${p.points} point${p.points > 1 ? "s" : ""} pour l'instant, encore jusqu'à ${p.maxRemaining} possibles.";

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text("Pick'em", style: AppTextStyles.pageTitle),
              Text(p.competitionName, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Text(status, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              if (editable) ...[
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _chooseChampion(p, picks, nodes),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text("Choisir mon champion"),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              SegmentedControl(labels: const ["Liste", "Colonnes"], selectedIndex: _view, onChanged: (i) => setState(() => _view = i)),
              const SizedBox(height: AppSpacing.md),
              if (_view == 1)
                _ColumnsView(match: p.matches.toList(), nodes: nodes, picks: picks, teams: teams, alive: aliveById, hidden: hidden, locked: p.locked)
              else
                for (final m in p.matches) ...[
                  _MatchPick(
                    match: m,
                    candidates: [for (final id in candidates[m.eventId] ?? const <String>[]) if (teams[id] != null) teams[id]!],
                    picked: picks[m.eventId],
                    editable: editable && !_saving,
                    hideResult: hidden,
                    alive: aliveById[m.eventId],
                    groupVotes: votesFor(m.eventId),
                    onPick: (id) => setState(() => _draft = prunePickem(nodes, {...picks, m.eventId: id})),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              if (p.locked) ...[
                const SizedBox(height: AppSpacing.md),
                _UpcomingPredictions(matches: [for (final m in p.matches) if (m.status == "scheduled" && m.participants.length >= 2 && m.winnerEntityId == null) m], teams: teams),
              ],
              const SizedBox(height: AppSpacing.md),
              _GroupsBlock(competitionId: widget.competitionId),
            ],
          ),
        ),
        if (editable)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: dirty && !_saving ? () => _save(p) : null, child: Text(_saving ? "Enregistrement…" : "Enregistrer mon tableau")),
            ),
          ),
      ],
    );
  }
}

typedef _GroupVote = ({String group, String team, bool? right});

class _MatchPick extends StatelessWidget {
  const _MatchPick({
    required this.match,
    required this.candidates,
    required this.picked,
    required this.editable,
    required this.hideResult,
    required this.alive,
    required this.groupVotes,
    required this.onPick,
  });

  final PickemMatchDto match;
  final List<PickemTeamDto> candidates;
  final String? picked;
  final bool editable;
  final bool hideResult;
  final bool? alive;
  final List<_GroupVote> groupVotes;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final winner = match.winnerEntityId;
    final settled = !hideResult && winner != null && picked != null;
    final correct = settled && picked == winner;
    // Un choix qui ne peut plus se réaliser, tant que le match n'est pas joué (masqué en sans spoil : ça en dirait trop).
    final dead = !hideResult && winner == null && picked != null && alive == false;
    return FramedCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(cardTitle(match.name), style: const TextStyle(fontWeight: FontWeight.w700))),
                Text("${match.weight} pt${match.weight > 1 ? "s" : ""}", style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.caption, fontWeight: FontWeight.w700)),
                if (settled) ...[const SizedBox(width: 6), Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 18, color: correct ? AppColors.win : AppColors.textTertiary)],
                if (dead) ...[const SizedBox(width: 6), const Icon(Icons.heart_broken_outlined, size: 18, color: AppColors.textTertiary)],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (candidates.isEmpty)
              const Text("Équipes à déterminer selon tes choix précédents.", style: TextStyle(color: AppColors.textTertiary))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in candidates)
                    ChoiceChip(
                      avatar: BracketTeamLogo(side: (label: t.name, code: t.shortName, imageUrl: t.imageUrl, entityId: t.entityId, score: null, won: false, lost: false)),
                      label: Text(t.shortName ?? t.name),
                      selected: picked == t.entityId,
                      showCheckmark: false,
                      onSelected: editable ? (_) => onPick(t.entityId) : null,
                    ),
                ],
              ),
            if (dead) const Padding(padding: EdgeInsets.only(top: AppSpacing.xs), child: Text("Ce choix ne peut plus se réaliser.", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption))),
            for (final v in groupVotes)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.groups_2_outlined, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(child: Text("${v.group} : ${v.team}", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption), overflow: TextOverflow.ellipsis)),
                    if (!hideResult && v.right != null) Icon(v.right! ? Icons.check_rounded : Icons.close_rounded, size: 16, color: v.right! ? AppColors.win : AppColors.textTertiary),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le tableau en colonnes, un tour par colonne : chaque choix est en or tant qu'il peut se réaliser, vert s'il était
/// juste, grisé et barré sinon. En sans spoil, tout reste en or (une couleur dirait qui a gagné).
class _ColumnsView extends StatelessWidget {
  const _ColumnsView({required this.match, required this.nodes, required this.picks, required this.teams, required this.alive, required this.hidden, required this.locked});

  final List<PickemMatchDto> match;
  final List<PickemNode> nodes;
  final Map<String, String> picks;
  final Map<String, PickemTeamDto> teams;
  final Map<String, bool?> alive;
  final bool hidden;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final rounds = pickemRounds(nodes);
    final last = rounds.values.fold(0, (a, b) => a > b ? a : b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var r = 0; r <= last; r++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r == last ? "FINALE" : "TOUR ${r + 1}", style: AppTextStyles.sectionTitle.copyWith(fontSize: 13, color: AppColors.brass)),
                    const SizedBox(height: AppSpacing.xs),
                    for (final m in match.where((m) => rounds[m.eventId] == r)) ...[_MiniMatch(match: m, team: teams[picks[m.eventId]], alive: alive[m.eventId], hidden: hidden, locked: locked), const SizedBox(height: AppSpacing.xs)],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniMatch extends StatelessWidget {
  const _MiniMatch({required this.match, required this.team, required this.alive, required this.hidden, required this.locked});

  final PickemMatchDto match;
  final PickemTeamDto? team;
  final bool? alive;
  final bool hidden;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final winner = match.winnerEntityId;
    final showResult = locked && !hidden;
    Color color = AppColors.gold;
    var struck = false;
    if (team == null) {
      color = AppColors.textTertiary;
    } else if (showResult && winner != null) {
      final right = winner == team!.entityId;
      color = right ? AppColors.win : AppColors.textTertiary;
      struck = !right;
    } else if (showResult && alive == false) {
      color = AppColors.textTertiary;
      struck = true;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadii.card / 2), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Row(
        children: [
          if (team != null) ...[
            BracketTeamLogo(side: (label: team!.name, code: team!.shortName, imageUrl: team!.imageUrl, entityId: team!.entityId, score: null, won: false, lost: false)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              team == null ? "—" : (team!.shortName ?? team!.name),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, decoration: struck ? TextDecoration.lineThrough : null),
            ),
          ),
          Text("${match.weight}", style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
        ],
      ),
    );
  }
}

/// Tournoi commencé : le tableau est fermé, mais les prochains matchs dont les deux équipes sont connues se pronostiquent
/// un par un (les pronostics de match, 3 points, comme ailleurs).
class _UpcomingPredictions extends ConsumerStatefulWidget {
  const _UpcomingPredictions({required this.matches, required this.teams});

  final List<PickemMatchDto> matches;
  final Map<String, PickemTeamDto> teams;

  @override
  ConsumerState<_UpcomingPredictions> createState() => _UpcomingPredictionsState();
}

class _UpcomingPredictionsState extends ConsumerState<_UpcomingPredictions> {
  final _sending = <String>{};

  Future<void> _predict(String eventId, String entityId) async {
    if (!_sending.add(eventId)) return;
    setState(() {});
    try {
      await ref.read(communityControllerProvider).predict(eventId, entityId);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      _sending.remove(eventId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.matches.isEmpty) return const SizedBox.shrink();
    final predictions = ref.watch(predictionsProvider).value ?? const <String, PredictionDto>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("PRONOSTIQUER LES PROCHAINS MATCHS"),
        const SizedBox(height: AppSpacing.xs),
        const Text("Le tableau est fermé : choisis le vainqueur des matchs à venir un par un (3 points chacun).", style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        for (final m in widget.matches)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: FramedCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cardTitle(m.name), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in m.participants)
                          if (widget.teams[id] case final t?)
                            ChoiceChip(
                              avatar: BracketTeamLogo(side: (label: t.name, code: t.shortName, imageUrl: t.imageUrl, entityId: t.entityId, score: null, won: false, lost: false)),
                              label: Text(t.shortName ?? t.name),
                              selected: predictions[m.eventId]?.pickedEntityId == id,
                              showCheckmark: false,
                              onSelected: _sending.contains(m.eventId) ? null : (_) => _predict(m.eventId, id),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }
}

/// Mes groupes sur ce tableau : qui a rempli le sien, puis, une fois verrouillé, leurs points et le vote du groupe.
class _GroupsBlock extends ConsumerWidget {
  const _GroupsBlock({required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(pickemGroupsProvider(competitionId)).value;
    if (data == null || data.groups.isEmpty) return const SizedBox.shrink();
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final groups = data.groups.toList()..sort((a, b) => a.rank.compareTo(b.rank));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("MES GROUPES"),
        const SizedBox(height: AppSpacing.sm),
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FramedCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (data.locked && !hidden)
                          Text("Vote du groupe : ${g.points} pts · n°${g.rank}", style: const TextStyle(color: AppColors.brass, fontSize: AppTypography.caption, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final m in g.members)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(m.isMe ? "${m.pseudo} (toi)" : m.pseudo)),
                            Text(
                              data.locked && !hidden ? "${m.points} pts" : "${m.filled} choisis",
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption),
                            ),
                          ],
                        ),
                      ),
                    if (!data.locked)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.xs),
                        child: Text("Les choix des autres apparaissent quand le tableau est verrouillé.", style: TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption)),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
