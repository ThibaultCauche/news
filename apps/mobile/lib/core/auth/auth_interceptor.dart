import "package:dio/dio.dart";
import "package:news_api_client/news_api_client.dart";
import "auth_store.dart";

const _retriedFlag = "retriedAfterRefresh";

/// Ajoute `Authorization` sur chaque requête, et rafraîchit le jeton d'accès
/// une fois sur un 401 avant de rejouer la requête (docs/03 §4). Un `Dio` sans
/// intercepteur pour le rafraîchissement lui-même : pas de boucle si le
/// rafraîchissement échoue à son tour.
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
    final refreshToken = _store.refreshToken;
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;
    if (err.response?.statusCode != 401 || alreadyRetried || refreshToken == null) {
      return handler.next(err);
    }

    try {
      final refreshApi = NewsApiClient(dio: Dio(BaseOptions(baseUrl: _baseUrl))).getAuthApi();
      final refreshed = await refreshApi.authControllerRefresh(refreshDto: RefreshDto((b) => b..refreshToken = refreshToken));
      final newAccessToken = refreshed.data!.accessToken;
      await _store.saveAccessToken(newAccessToken);

      final retryOptions = err.requestOptions;
      retryOptions.headers["Authorization"] = "Bearer $newAccessToken";
      retryOptions.extra[_retriedFlag] = true;
      final retried = await Dio(BaseOptions(baseUrl: _baseUrl)).fetch(retryOptions);
      handler.resolve(retried);
    } catch (_) {
      // Le compte n'existe peut-être plus (`DELETE /v1/me`) : un prochain
      // lancement en recréera un (`ensureAnonymousAccount`).
      await _store.clear();
      handler.next(err);
    }
  }
}
