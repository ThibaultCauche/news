import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../../core/settings_provider.dart";
import "../../theme/tokens.dart";
import "../../widgets/async_view.dart";
import "../../widgets/bracket_match_card.dart";
import "../../widgets/ornate_frame.dart";
import "../../widgets/section_label.dart";
import "../account/account_gate.dart";

/// Pronostic d'une phase suisse (`GET /v1/competitions/:id/pick`, J23) : les équipes qu'on pense voir se qualifier,
/// à choisir avant le premier match. Le serveur décide du verrouillage.
final stagePickProvider = FutureProvider.autoDispose.family<StagePickDto?, String>((ref, competitionId) async {
  // Invité : pas de pronostic (il faut un compte, comme pour les pronostics de match).
  if (!ref.watch(signedInProvider)) return null;
  final response = await ref.watch(apiClientProvider).getCommunityApi().communityControllerGetStagePick(id: competitionId);
  return response.data;
});

class StagePickController {
  StagePickController(this._ref);

  final Ref _ref;

  /// Enregistre le pronostic ; `false` si la personne a renoncé à se connecter.
  Future<bool> save(String competitionId, List<String> entityIds) async {
    if (!await ensureAccount(_ref)) return false;
    await _ref.read(apiClientProvider).getCommunityApi().communityControllerPutStagePick(
          id: competitionId,
          putStagePickDto: PutStagePickDto((b) => b..entityIds.replace(entityIds)),
        );
    _ref.invalidate(stagePickProvider(competitionId));
    return true;
  }
}

final stagePickControllerProvider = Provider((ref) => StagePickController(ref));

/// La carte « Ton pronostic » au-dessus de la phase suisse : invitation à choisir avant le début, puis le décompte
/// (bonnes, ratées, en cours) une fois l'étape lancée. Rien tant que les équipes ne sont pas connues.
class StagePickCard extends ConsumerWidget {
  const StagePickCard({super.key, required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInProvider);
    final pick = ref.watch(stagePickProvider(competitionId)).value;
    // Un invité voit l'invitation ; la connexion est demandée au moment d'enregistrer.
    if (!signedIn) return const SizedBox.shrink();
    if (pick == null || !pick.open) return const SizedBox.shrink();
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FramedCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel("TON PRONOSTIC"),
              const SizedBox(height: AppSpacing.xs),
              ..._content(context, ref, pick, hideResults: hidden),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, StagePickDto pick, {required bool hideResults}) {
    final names = {for (final t in pick.teams) t.entityId: t};
    if (!pick.locked) {
      final chosen = pick.picks.length;
      return [
        Text(
          chosen == 0
              ? "Quelles ${pick.max} équipes vont se qualifier ? Choisis avant le début de la phase suisse."
              : "$chosen équipe${chosen > 1 ? "s" : ""} choisie${chosen > 1 ? "s" : ""} sur ${pick.max}. Tu peux changer jusqu'au début.",
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(onPressed: () => _openSheet(context, ref, pick), child: Text(chosen == 0 ? "Choisir mes équipes" : "Modifier")),
      ];
    }
    if (pick.picks.isEmpty) {
      return const [Text("Le pronostic est fermé : la phase suisse a commencé.", style: TextStyle(color: AppColors.textSecondary))];
    }
    final score = pick.score;
    final points = pick.points;
    final summary = hideResults || score == null
        ? "${pick.picks.length} équipes choisies. Résultats masqués (sans spoil)."
        : "${score.correct} bonne${score.correct > 1 ? "s" : ""} · ${score.wrong} ratée${score.wrong > 1 ? "s" : ""} · ${score.pending} en cours${points == null ? "" : " · $points point${points > 1 ? "s" : ""}"}";
    return [
      Text(summary, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in pick.picks)
            if (names[id] case final team?)
              Chip(
                avatar: BracketTeamLogo(side: (label: team.name, code: team.shortName, imageUrl: team.imageUrl, entityId: team.entityId, score: null, won: false, lost: false)),
                label: Text(team.shortName ?? team.name),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: hideResults ? AppColors.surfaceBorder : _stateColor(team.state)),
              ),
        ],
      ),
    ];
  }

  Color _stateColor(StagePickTeamDtoStateEnum state) => switch (state) {
        StagePickTeamDtoStateEnum.qualified => AppColors.win,
        StagePickTeamDtoStateEnum.eliminated => AppColors.textTertiary,
        _ => AppColors.brass,
      };

  void _openSheet(BuildContext context, WidgetRef ref, StagePickDto pick) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickSheet(competitionId: competitionId, pick: pick),
    );
  }
}

class _PickSheet extends ConsumerStatefulWidget {
  const _PickSheet({required this.competitionId, required this.pick});

  final String competitionId;
  final StagePickDto pick;

  @override
  ConsumerState<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends ConsumerState<_PickSheet> {
  late final Set<String> _chosen = {...widget.pick.picks};
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final saved = await ref.read(stagePickControllerProvider).save(widget.competitionId, _chosen.toList());
      if (saved && mounted) navigator.pop();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.pick.max;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text("Qui se qualifie ?", style: Theme.of(context).textTheme.titleLarge)),
                  Text("${_chosen.length}/$max", style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final team in widget.pick.teams)
                    CheckboxListTile(
                      value: _chosen.contains(team.entityId),
                      // Au maximum : on ne peut plus cocher, seulement décocher.
                      onChanged: (_chosen.length >= max && !_chosen.contains(team.entityId))
                          ? null
                          : (on) => setState(() => on == true ? _chosen.add(team.entityId) : _chosen.remove(team.entityId)),
                      secondary: BracketTeamLogo(
                        side: (label: team.name, code: team.shortName, imageUrl: team.imageUrl, entityId: team.entityId, score: null, won: false, lost: false),
                      ),
                      title: Text(team.name),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? "Enregistrement…" : "Enregistrer")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
