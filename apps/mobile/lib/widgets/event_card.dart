import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../core/date_x.dart";
import "../domain/event_status.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";
import "live_dot.dart";

/// Ligne de match réutilisée par l'agenda, la saison et l'accueil — heure à
/// gauche, score/statut à droite, comme l'écran 09 des maquettes (`docs/02`) :
/// mêmes règles d'affichage quel que soit l'écran (règle 12 — la couleur
/// porte toujours le même sens). Sans spoil (écran 15, J6) : [scoresHidden]
/// masque le score d'un match terminé, lu une seule fois par l'écran appelant
/// (`userSettingProvider`) plutôt que par chaque carte — pas d'appui long ici,
/// seulement sur l'écran du match (`NextMatchScreen`).
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.scoresHidden, this.onTap, this.followedEntityIds = const {}});

  /// Score d'un match terminé masqué (réglage sans spoil du compte).
  final bool scoresHidden;

  final EventSummaryDto event;
  final VoidCallback? onTap;

  /// `entityId` des équipes/joueurs suivis : affichés en or
  /// (`docs/maquettes/specs/01-valorant-saison.md`, `06-groupes.md`), comme
  /// `highlightedEventIds` dans `bracket_screen.dart`.
  final Set<String> followedEntityIds;

  Widget _buildTitle(TextStyle? style) {
    if (event.participants.length != 2) {
      return Text(event.name, style: style, overflow: TextOverflow.ellipsis);
    }
    final a = event.participants[0];
    final b = event.participants[1];
    TextStyle? colorFor(EventParticipantDto p) =>
        followedEntityIds.contains(p.entityId) ? const TextStyle(color: AppColors.gold) : null;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: a.name, style: colorFor(a)),
          const TextSpan(text: " – "),
          TextSpan(text: b.name, style: colorFor(b)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  String? get _scoreLine {
    if (event.participants.length != 2) return null;
    final a = event.participants[0].score;
    final b = event.participants[1].score;
    if (a == null || b == null) return null;
    return "$a-$b";
  }

  @override
  Widget build(BuildContext context) {
    final status = event.status.statusKind;
    final textTheme = Theme.of(context).textTheme;
    final score = status == EventStatusKind.finished && scoresHidden ? null : _scoreLine;

    Widget? trailing;
    if (status == EventStatusKind.live || status == EventStatusKind.finished) {
      trailing = Text(
        score ?? status.label,
        style: AppTextStyles.bodyLargeStrong.copyWith(
          color: status == EventStatusKind.live ? AppColors.live : AppColors.textPrimary,
        ),
      );
    } else if (status == EventStatusKind.postponed) {
      trailing = Text(status.label, style: textTheme.bodySmall?.copyWith(color: status.color));
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: event.startsAt.toDateTime != null
                  ? Text(DateFormat.Hm("fr_FR").format(event.startsAt.toDateTime!.toLocal()), style: AppTextStyles.bodyLargeStrong)
                  : null,
            ),
            if (status == EventStatusKind.live) ...[const LiveDot(), const SizedBox(width: AppSpacing.sm)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(AppTextStyles.bodyLargeStrong),
                  Text(
                    [event.competition.name, if (event.bestOf != null) "BO${event.bestOf}"].join(" · "),
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing],
          ],
        ),
      ),
    );
  }
}
