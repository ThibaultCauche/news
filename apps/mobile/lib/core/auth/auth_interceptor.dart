import "package:dio/dio.dart";
import "package:news_api_client/news_api_client.dart";
import "auth_store.dart";

const _retriedFlag = "retriedAfterRefresh";

/// Ajoute `Authorization` sur chaque requête, et sur un 401 rafraîchit le
/// jeton d'accès avant de rejouer la requête (docs/03 §4). Si le rafraîchissement
/// échoue aussi (jeton de rafraîchissement expiré, ou compte supprimé côté
/// serveur — `DELETE /v1/me`), un nouveau compte anonyme est recréé à la volée :
/// sans ça, l'appli resterait bloquée sur tout appel authentifié jusqu'au
/// prochain lancement (`ensureAnonymousAccount` ne s'exécute qu'au démarrage).
/// Un `Dio` nu pour ces deux appels : pas de boucle si l'un d'eux échoue à son tour.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._baseUrl);

  final AuthStore _store;
  final String _baseUrl;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _store.accessToken;
    if (token != null) options.headers["Authorization"] = "Bearer $token";
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;
    if (err.response?.statusCode != 401 || alreadyRetried) {
      return handler.next(err);
    }

    try {
      final bareDio = Dio(BaseOptions(baseUrl: _baseUrl));
      final newAccessToken = await _refreshOrRecreateAccount(bareDio);

      final retryOptions = err.requestOptions;
      retryOptions.headers["Authorization"] = "Bearer $newAccessToken";
      retryOptions.extra[_retriedFlag] = true;
      final retried = await bareDio.fetch(retryOptions);
      handler.resolve(retried);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String> _refreshOrRecreateAccount(Dio dio) async {
    final refreshToken = _store.refreshToken;
    if (refreshToken != null) {
      try {
        final refreshed = await NewsApiClient(
          dio: dio,
        ).getAuthApi().authControllerRefresh(refreshDto: RefreshDto((b) => b..refreshToken = refreshToken));
        final newAccessToken = refreshed.data!.accessToken;
        await _store.saveAccessToken(newAccessToken);
        return newAccessToken;
      } catch (_) {
        // Jeton de rafraîchissement expiré ou compte introuvable : on retombe
        // sur la recréation ci-dessous plutôt que d'abandonner.
      }
    }
    final created = await NewsApiClient(dio: dio).getAuthApi().authControllerCreateAnonymous();
    final tokens = created.data!;
    await _store.saveTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
    return tokens.accessToken;
  }
}
