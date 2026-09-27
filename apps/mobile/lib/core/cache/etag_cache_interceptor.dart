import "dart:convert";

import "package:dio/dio.dart";
import "cache_store.dart";

const _cacheKeyExtra = "cacheKey";

/// Envoie `If-None-Match`, enregistre l'`ETag` de chaque réponse `GET`, et
/// rejoue le dernier corps connu quand l'API répond `304` ou quand la requête
/// échoue faute de réseau (mode avion). Un seul endroit pour les deux règles
/// de `docs/03` §4 ("`ETag` partout") et §11 ("hors ligne d'abord").
class ETagCacheInterceptor extends Interceptor {
  ETagCacheInterceptor(this._store);

  final CacheStore _store;

  static String keyFor(RequestOptions options) {
    final uri = options.uri;
    return uri.hasQuery ? "${uri.path}?${uri.query}" : uri.path;
  }

  // Le cache est un confort (ETag, mode avion), jamais une condition pour
  // qu'une requête aboutisse : une erreur de stockage local (drift/IndexedDB
  // indisponible, quota dépassé…) ne doit jamais faire échouer l'appel API.
  Future<CachedEntry?> _readSafe(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.method != "GET") return handler.next(options);
    final key = keyFor(options);
    options.extra[_cacheKeyExtra] = key;
    final cached = await _readSafe(key);
    if (cached?.etag != null) {
      options.headers["If-None-Match"] = cached!.etag;
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final key = response.requestOptions.extra[_cacheKeyExtra] as String?;
    if (key != null && response.statusCode == 200) {
      try {
        await _store.write(
          key,
          body: jsonEncode(response.data),
          etag: response.headers.value("etag"),
        );
      } catch (_) {
        // Rien à faire : la réponse reste servie, juste pas mise en cache.
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final key = err.requestOptions.extra[_cacheKeyExtra] as String?;
    final isNotModified = err.response?.statusCode == 304;
    // err.response == null : coupure réseau pure (avion, DNS...). 502/503/504 :
    // un reverse proxy devant l'API (Tailscale Funnel en prod) répond lui-même
    // alors que le backend est mort — vécu en vrai, aucun des deux cas ne se
    // recoupe (err.response existe, juste pas avec le statut 304 attendu).
    final isServerUnreachable = err.response == null || [502, 503, 504].contains(err.response?.statusCode);
    if (key != null && (isNotModified || isServerUnreachable)) {
      final cached = await _readSafe(key);
      if (cached != null) {
        return handler.resolve(
          Response(
            requestOptions: err.requestOptions,
            statusCode: 200,
            data: jsonDecode(cached.body),
          ),
        );
      }
    }
    handler.next(err);
  }
}
