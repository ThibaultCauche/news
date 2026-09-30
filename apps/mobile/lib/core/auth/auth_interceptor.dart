import "package:dio/dio.dart";
import "package:news_api_client/news_api_client.dart";
import "auth_store.dart";

const _retriedFlag = "retriedAfterRefresh";

/// Ajoute `Authorization` quand on est connecté, et sur un 401 rafraîchit le jeton d'accès
/// avant de rejouer la requête (docs/03 §4). Si le rafraîchissement échoue aussi (jeton
/// expiré après 180 jours, ou compte supprimé côté serveur — `DELETE /v1/me`), la session
/// est fermée (`onSignedOut`) : l'appli retombe en mode invité, et l'utilisateur se
/// reconnecte quand une action l'exige (J11 : plus de compte anonyme recréé à la volée).
/// Un `Dio` nu pour le rafraîchissement : pas de boucle si l'appel échoue à son tour.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._baseUrl, {required this.onSignedOut});

  final AuthStore _store;
  final String _baseUrl;
  final void Function() onSignedOut;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _store.accessToken;
    if (token != null) options.headers["Authorization"] = "Bearer $token";
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;
    // Invité (aucun jeton) : un 401 n'a rien à rafraîchir.
    if (err.response?.statusCode != 401 || alreadyRetried || _store.accessToken == null) {
      return handler.next(err);
    }

    final bareDio = Dio(BaseOptions(baseUrl: _baseUrl));
    final newAccessToken = await _refresh(bareDio);
    if (newAccessToken == null) {
      await _store.clear();
      onSignedOut();
      return handler.next(err);
    }
    try {
      final retryOptions = err.requestOptions;
      retryOptions.headers["Authorization"] = "Bearer $newAccessToken";
      retryOptions.extra[_retriedFlag] = true;
      handler.resolve(await bareDio.fetch(retryOptions));
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String?> _refresh(Dio dio) async {
    final refreshToken = _store.refreshToken;
    if (refreshToken == null) return null;
    try {
      final refreshed = await NewsApiClient(
        dio: dio,
      ).getAuthApi().authControllerRefresh(refreshDto: RefreshDto((b) => b..refreshToken = refreshToken));
      final newAccessToken = refreshed.data!.accessToken;
      await _store.saveAccessToken(newAccessToken);
      return newAccessToken;
    } catch (_) {
      return null;
    }
  }
}
