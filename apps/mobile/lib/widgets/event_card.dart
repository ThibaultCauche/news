import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:news_api_client/news_api_client.dart";
import "../core/date_x.dart";
import "../domain/event_status.dart";
import "../theme/tokens.dart";
import "live_dot.dart";

/// Ligne de match réutilisée par l'agenda, la saison et l'accueil — heure à
/// gauche, score/statut à droite, comme l'écran 09 des maquettes (`docs/02`) :
/// mêmes règles d'affichage quel que soit l'écran (règle 12 — la couleur
/// porte toujours le même sens).
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final EventSummaryDto event;
  final VoidCallback? onTap;

  String get _title {
    if (event.participants.length == 2) {
      return "${event.participants[0].name} – ${event.participants[1].name}";
    }
    return event.name;
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
    final score = _scoreLine;

    Widget? trailing;
    if (status == EventStatusKind.live || status == EventStatusKind.finished) {
      trailing = Text(
        score ?? status.label,
        style: textTheme.titleLarge?.copyWith(
          fontSize: 16,
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
                  ? Text(DateFormat.Hm("fr_FR").format(event.startsAt.toDateTime!.toLocal()), style: textTheme.bodyMedium)
                  : null,
            ),
            if (status == EventStatusKind.live) ...[const LiveDot(), const SizedBox(width: AppSpacing.sm)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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
