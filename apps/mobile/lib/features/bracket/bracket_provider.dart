import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "../../core/api_providers.dart";

/// En-tête, frise et standings d'une compétition (`/v1/competitions/:id`, J2) —
/// réutilisé au J5 pour les groupes (écran 06) et le « 3 vies » (écran 14),
/// qui n'ont besoin que des classements déjà recalculés côté worker.
final competitionDetailProvider = FutureProvider.autoDispose.family<CompetitionResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetById(id: id);
  return response.data!;
});

/// Nœuds + liens de bracket (`/v1/competitions/:id/bracket`, J5) — arbre
/// radial (02/07), repêchage (05) et arbre de poule (06, `GroupBracketTree`).
final bracketProvider = FutureProvider.autoDispose.family<BracketResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetBracket(id: id);
  return response.data!;
});

/// Les compétitions "poule" (ex. "Group A"…"Group D") des enfants d'une
/// étape, triées par nom — sans quoi l'ordre suit celui renvoyé par l'API
/// (pas garanti alphabétique) et les poules s'affichent dans le désordre.
/// Partagée entre l'onglet Groupes (`bracket_screen.dart`) et la carte
/// "Maintenant" de l'écran Saison (`valorant_season_screen.dart`).
List<String> groupCompetitionIds(List<CompetitionChildDto> children) {
  final groups = children.where((c) => c.name.toLowerCase().contains("group")).toList()..sort((a, b) => a.name.compareTo(b.name));
  return groups.map((c) => c.id).toList();
}

/// Une ligne par participant si le match est résolu, sinon un placeholder
/// « Perdant de … »/« Gagnant de … » par lien entrant (écran 05). Ici plutôt
/// que dans `bracket_screen.dart` : réutilisée par `GroupBracketTree`
/// (`widgets/group_bracket_tree.dart`), qui ne peut pas importer
/// `bracket_screen.dart` sans créer un import circulaire (l'inverse est déjà
/// vrai : `bracket_screen.dart` affiche `GroupBracketTree` dans son onglet
/// Groupes).
List<(String label, String? score, bool isWinner)> bracketMatchRows(
  BracketNodeDto node,
  List<BracketLinkDto> incoming,
  Map<String, BracketNodeDto> byId,
) {
  if (node.participants.isNotEmpty) {
    return [for (final p in node.participants) (p.shortName ?? p.name, p.score?.toString(), p.isWinner == true)];
  }
  return [for (final l in incoming) (_placeholderLabel(l, byId), null, false)];
}

String _placeholderLabel(BracketLinkDto link, Map<String, BracketNodeDto> byId) {
  final from = byId[link.fromEventId];
  final verb = link.outcome == "winner" ? "Gagnant de" : "Perdant de";
  if (from == null) return "$verb un match à venir";
  final fromLabel = from.participants.isEmpty ? from.name : from.participants.map((p) => p.shortName ?? p.name).join(" vs ");
  return "$verb $fromLabel";
}
