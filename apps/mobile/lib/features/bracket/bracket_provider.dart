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
/// radial (02/07) et repêchage (05).
final bracketProvider = FutureProvider.autoDispose.family<BracketResponseDto, String>((ref, id) async {
  final response = await ref.watch(apiClientProvider).getCompetitionsApi().competitionsControllerGetBracket(id: id);
  return response.data!;
});
