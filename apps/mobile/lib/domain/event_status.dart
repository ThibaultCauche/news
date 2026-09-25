import "package:flutter/widgets.dart";
import "../theme/tokens.dart";

enum EventStatusKind { scheduled, live, finished, postponed, cancelled, unknown }

/// `status` vient tel quel de l'API (`packages/domain` côté backend :
/// scheduled/live/finished/postponed/cancelled) : ce fichier est la seule
/// traduction en français et en couleur, réutilisée partout dans l'appli.
extension EventStatusParsing on String {
  EventStatusKind get statusKind => switch (this) {
    "scheduled" => EventStatusKind.scheduled,
    "live" => EventStatusKind.live,
    "finished" => EventStatusKind.finished,
    "postponed" => EventStatusKind.postponed,
    "cancelled" => EventStatusKind.cancelled,
    _ => EventStatusKind.unknown,
  };
}

extension EventStatusLabel on EventStatusKind {
  String get label => switch (this) {
    EventStatusKind.scheduled => "À venir",
    EventStatusKind.live => "En direct",
    EventStatusKind.finished => "Terminé",
    EventStatusKind.postponed => "Reporté",
    EventStatusKind.cancelled => "Annulé",
    EventStatusKind.unknown => "",
  };

  Color get color => switch (this) {
    EventStatusKind.live => AppColors.live,
    EventStatusKind.finished => AppColors.textSecondary,
    EventStatusKind.postponed => AppColors.textTertiary,
    EventStatusKind.cancelled => AppColors.textTertiary,
    _ => AppColors.textSecondary,
  };
}
