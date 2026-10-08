import "package:news_api_client/news_api_client.dart";

import "../../core/games.dart";
import "../bracket/bracket_model.dart" show scheduleLabel;

/// Appli modulée selon la personne (J28, #M6) : ce qui se calcule sans écran. On module l'ordre des sections et le
/// filtre par défaut, jamais la barre d'onglets.

/// Un grand rendez-vous de sa catégorie favorite passe avant les autres ; l'ordre du serveur (direct d'abord, puis
/// par date) est gardé à l'intérieur de chaque groupe.
List<MajorCompetitionDto> orderMajorsFor(String? favoriteCategory, List<MajorCompetitionDto> majors) {
  if (favoriteCategory == null) return majors;
  final mine = [for (final m in majors) if (gameCategory(m.game) == favoriteCategory) m];
  final others = [for (final m in majors) if (gameCategory(m.game) != favoriteCategory) m];
  return [...mine, ...others];
}

/// La suggestion d'une autre catégorie se montre au plus une fois par semaine : après l'avoir fermée ou ouverte,
/// elle disparaît pendant 7 jours.
const suggestionPause = Duration(days: 7);

bool suggestionVisible(DateTime? dismissedAt, DateTime now) => dismissedAt == null || now.difference(dismissedAt) >= suggestionPause;

/// La phrase de la suggestion, par gabarit : « Champions 2026 est en cours. » ou « Formule 1 2026 commence demain. ».
String suggestionSentence(HomeSuggestionDto suggestion, DateTime now) {
  if (suggestion.live) return "${suggestion.competitionName} est en cours.";
  final start = suggestion.startsAt == null ? null : DateTime.parse(suggestion.startsAt!).toLocal();
  return start == null ? "${suggestion.competitionName} arrive bientôt." : "${suggestion.competitionName} commence ${scheduleLabel(start, now)}.";
}
