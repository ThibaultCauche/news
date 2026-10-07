import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/settings_provider.dart";
import "../../domain/event_status.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/compact_match_row.dart";
import "../../widgets/section_card.dart";
import "../bracket/bracket_provider.dart";
import "../bracket/pickem.dart";
import "../competitions/game_screen.dart" show openCompetitionPage;
import "../forum/forum_providers.dart";
import "../../core/games.dart";
import "../next_match/next_match_screen.dart";
import "../team/team_screen.dart";

/// Résumé d'un match à partir de sa fiche : les cartes partagées n'ont que l'identifiant du match, la fiche
/// donne les données du moment (score, statut), pas celles du jour du partage.
EventSummaryDto summaryOf(EventDetailResponseDto d) => EventSummaryDto(
  (b) => b
    ..id = d.id
    ..kind = d.kind
    ..name = d.name
    ..status = d.status
    ..startsAt = d.startsAt
    ..endsAt = d.endsAt
    ..bestOf = d.bestOf
    ..importance = d.importance
    ..competition.replace(d.competition)
    ..participants.replace(d.participants),
);

/// Carte d'un message partagé (match, compétition, pronostic) : dessinée par l'appli avec les données en
/// direct et le sans spoil du lecteur (score flouté d'un match terminé, comme partout ailleurs).
class SharedCard extends ConsumerWidget {
  const SharedCard({super.key, required this.shared, required this.pseudo});

  final ForumSharedDto shared;
  final String pseudo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (shared.kind) {
      ForumSharedDtoKindEnum.competition => _CompetitionCard(competitionId: shared.refId),
      ForumSharedDtoKindEnum.prediction => _PredictionCard(shared: shared, pseudo: pseudo),
      ForumSharedDtoKindEnum.team => _TeamCard(entityId: shared.refId),
      ForumSharedDtoKindEnum.pickem => _PickemShareCard(shared: shared, pseudo: pseudo),
      _ => _EventCard(eventId: shared.refId),
    };
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId));
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    return event.when(
      data: (e) => CompactMatchRow(event: summaryOf(e), scoresHidden: hidden, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: eventId)))),
      error: (_, _) => const _CardNote(icon: Icons.sports_esports_outlined, text: "Ce match n'est plus disponible."),
      loading: () => const SizedBox(height: CompactMatchRow.height, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
    );
  }
}

class _TeamCard extends ConsumerWidget {
  const _TeamCard({required this.entityId});

  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(entityProvider(entityId)).value;
    if (team == null) return const _CardNote(icon: Icons.shield_outlined, text: "Équipe");
    return SectionCard(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(entityId: entityId, breadcrumb: "Retour"))),
        child: Row(
          children: [
            Icon(team.kind == "player" ? Icons.person_outline_rounded : Icons.shield_outlined, color: AppColors.brass),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: AppTextStyles.bodyLargeStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (team.game != null) Text(gameLabel(team.game!), style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CompetitionCard extends ConsumerWidget {
  const _CompetitionCard({required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(competitionId)).value;
    if (detail == null) return const _CardNote(icon: Icons.emoji_events_outlined, text: "Compétition");
    // « Playoffs » seul ne dit rien : on ajoute la série qui le contient (« Champions 2026 · Playoffs »).
    final parentName = detail.parentId == null ? null : ref.watch(competitionDetailProvider(detail.parentId!)).value?.name;
    final title = parentName == null || detail.name.contains(parentName) ? detail.name : "$parentName · ${detail.name}";
    return SectionCard(
      child: InkWell(
        onTap: () => openCompetitionPage(context, id: detail.id, name: detail.name, status: detail.status),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_outlined, color: AppColors.brass),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyLargeStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (detail.status != null) Text(detail.status!.statusKind.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Pronostic partagé : le serveur ne renvoie le choix qu'une fois le match commencé (ou pour son auteur).
class _PredictionCard extends ConsumerWidget {
  const _PredictionCard({required this.shared, required this.pseudo});

  final ForumSharedDto shared;
  final String pseudo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(shared.refId)).value;
    final match = event == null ? "ce match" : event.participants.map((p) => p.shortName ?? p.name).join(" – ");
    final pickedId = shared.pickedEntityId;
    String text;
    if (shared.locked || pickedId == null) {
      text = "Pronostic sur $match : dévoilé au début du match.";
    } else {
      final team = event?.participants.where((p) => p.entityId == pickedId).firstOrNull;
      final score = shared.pickedScore != null && shared.otherScore != null ? " (${shared.pickedScore}-${shared.otherScore})" : "";
      text = "$pseudo mise sur ${team == null ? "?" : (team.shortName ?? team.name)}$score pour $match.";
    }
    return SectionCard(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NextMatchScreen(eventId: shared.refId))),
        child: Row(
          children: [
            Icon(shared.locked ? Icons.lock_outline_rounded : Icons.emoji_events_outlined, color: AppColors.gold),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text, style: AppTextStyles.bodyStrong)),
          ],
        ),
      ),
    );
  }
}

/// Tableau de pick'em partagé : le nombre de choix se voit toujours, le champion et les points au début du tournoi
/// (décidé par le serveur). Un appui ouvre mon propre tableau pour cette compétition.
class _PickemShareCard extends ConsumerWidget {
  const _PickemShareCard({required this.shared, required this.pseudo});

  final ForumSharedDto shared;
  final String pseudo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(shared.refId)).value;
    final parentName = detail?.parentId == null ? null : ref.watch(competitionDetailProvider(detail!.parentId!)).value?.name;
    final name = detail == null ? "ce tournoi" : (parentName == null || detail.name.contains(parentName) ? detail.name : "$parentName · ${detail.name}");
    final hidden = ref.watch(userSettingProvider).value?.spoilerFree ?? true;
    final champion = shared.pickedEntityId == null ? null : ref.watch(entityProvider(shared.pickedEntityId!)).value;
    final picked = shared.pickemPicked ?? 0;
    final total = shared.pickemTotal ?? 0;
    final text = shared.locked
        ? "$pseudo a rempli son tableau ($picked/$total matchs) pour $name. Il sera dévoilé au début du tournoi."
        : "$pseudo mise sur ${champion?.name ?? "?"} pour $name ($picked/$total matchs)${hidden || shared.pickemPoints == null ? "" : ", ${shared.pickemPoints} pts"}.";
    return SectionCard(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PickemScreen(competitionId: shared.refId))),
        child: Row(
          children: [
            Icon(shared.locked ? Icons.lock_outline_rounded : Icons.account_tree_outlined, color: AppColors.brass),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text, style: AppTextStyles.bodyStrong)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _CardNote extends StatelessWidget {
  const _CardNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(children: [Icon(icon, color: AppColors.textTertiary), const SizedBox(width: AppSpacing.md), Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary)))]),
    );
  }
}

/// Sondage lancé par l'équipe de l'appli : un choix par personne, modifiable (re-toucher son choix le retire).
class PollCard extends ConsumerStatefulWidget {
  const PollCard({super.key, required this.threadId, required this.messageId, required this.question, required this.poll});

  final String threadId;
  final String messageId;
  final String question;
  final ForumPollDto poll;

  @override
  ConsumerState<PollCard> createState() => _PollCardState();
}

String _endsIn(DateTime end) {
  final d = end.toLocal().difference(DateTime.now());
  if (d.inMinutes < 60) return "se termine dans ${d.inMinutes < 1 ? 1 : d.inMinutes} min";
  if (d.inHours < 48) return "se termine dans ${d.inHours} h";
  return "se termine dans ${d.inDays} j";
}

class _PollCardState extends ConsumerState<PollCard> {
  // Choix affiché tout de suite le temps de l'appel (`-1` = vote retiré).
  int? _pending;
  bool _busy = false;

  Future<void> _vote(int index, int? current) async {
    if (_busy) return;
    final next = current == index ? null : index;
    setState(() {
      _busy = true;
      _pending = next ?? -1;
    });
    try {
      await ref.read(forumControllerProvider).vote(widget.threadId, widget.messageId, next);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.poll;
    final mine = _pending == null ? poll.myVote?.toInt() : (_pending == -1 ? null : _pending);
    // Les compteurs suivent le choix affiché tout de suite : un vote de plus pour la nouvelle option, un de moins pour l'ancienne.
    final votes = [for (final o in poll.options) o.votes.toInt()];
    if (_pending != null) {
      final before = poll.myVote?.toInt();
      if (before != null && before < votes.length) votes[before]--;
      if (mine != null && mine < votes.length) votes[mine]++;
    }
    final total = votes.fold<int>(0, (a, b) => a + b);
    final closed = poll.closed;
    final top = votes.fold<int>(0, (a, b) => a > b ? a : b);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_outlined, size: 18, color: AppColors.brass),
              const SizedBox(width: AppSpacing.xs),
              Text("Sondage", style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.question, style: AppTextStyles.bodyLargeStrong),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, option) in poll.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.chip),
                onTap: closed ? null : () => _vote(i, mine),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: total == 0 ? 0 : votes[i] / total,
                        child: DecoratedBox(decoration: BoxDecoration(color: AppColors.brass.withValues(alpha: mine == i ? 0.32 : 0.14), borderRadius: BorderRadius.circular(AppRadii.chip))),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(border: Border.all(color: mine == i ? AppColors.brass : AppColors.surfaceBorderHighlight), borderRadius: BorderRadius.circular(AppRadii.chip)),
                      child: Row(
                        children: [
                          Icon(mine == i ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: mine == i ? AppColors.brass : AppColors.textTertiary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(option.label, style: closed && top > 0 && votes[i] == top ? AppTextStyles.bodyStrong : null)),
                          Text("${votes[i]}", style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            [
              total == 0 ? "Aucun vote pour l'instant." : "$total vote${total > 1 ? "s" : ""}",
              if (closed) "Sondage terminé" else if (poll.endsAt != null) _endsIn(poll.endsAt!),
            ].join(" · "),
            style: const TextStyle(color: AppColors.textTertiary, fontSize: AppTypography.caption),
          ),
        ],
      ),
    );
  }
}
