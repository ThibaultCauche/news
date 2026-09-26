import "package:dio/dio.dart";
import "package:news_api_client/news_api_client.dart";
import "auth_store.dart";

/// Compte anonyme créé au tout premier lancement (docs/03 §4, docs/04 J4) :
/// pas d'inscription. `Dio` nu, sans intercepteur — cet appel n'a rien à
/// envoyer ni à mettre en cache.
Future<void> ensureAnonymousAccount(AuthStore store, String baseUrl) async {
  if (store.accessToken != null) return;
  final api = NewsApiClient(dio: Dio(BaseOptions(baseUrl: baseUrl)));
  final response = await api.getAuthApi().authControllerCreateAnonymous();
  final tokens = response.data!;
  await store.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
}
