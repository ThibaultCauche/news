import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "auth/auth_interceptor.dart";
import "auth/auth_store.dart";
import "cache/app_database.dart";
import "cache/cache_store.dart";
import "cache/etag_cache_interceptor.dart";

/// En dev, l'API tourne sur la machine hôte : sur Android, `adb reverse
/// tcp:3000 tcp:3000` fait pointer `localhost` de l'appareil (émulateur ou
/// téléphone en USB) vers `localhost` de l'hôte, comme sur les autres cibles.
/// Pour un build bêta/prod (J7) : `flutter build appbundle
/// --dart-define=API_BASE_URL=https://machine.tailnet.ts.net/news` (suffixe
/// de chemin si l'API est montée dessous, `PUBLIC_PATH_PREFIX`, docs/05 §3).
String resolveApiBaseUrl() => const String.fromEnvironment("API_BASE_URL", defaultValue: "http://localhost:3000");

// Fourni par `main()` via `ProviderScope(overrides: ...)`, une fois
// `SharedPreferences` chargé (docs/04 J4) — jamais construit avec sa valeur
// par défaut en dehors des tests.
final authStoreProvider = Provider<AuthStore>((ref) => throw UnimplementedError("authStoreProvider non initialisé"));

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final cacheStoreProvider = Provider<CacheStore>((ref) {
  return CacheStore(ref.watch(appDatabaseProvider));
});

final apiClientProvider = Provider<NewsApiClient>((ref) {
  final store = ref.watch(cacheStoreProvider);
  final auth = ref.watch(authStoreProvider);
  final baseUrl = resolveApiBaseUrl();
  // Sans délai explicite, Dio attend indéfiniment une connexion morte (vécu
  // en vrai : NAS coupé, spinner bloqué au lieu du repli hors ligne, faute
  // d'erreur pour déclencher ETagCacheInterceptor.onError, docs/03 §11).
  final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
  // Ordre important : la phase requête va du 1er au dernier intercepteur
  // ajouté, la phase erreur en sens inverse — l'ETag doit d'abord laisser
  // passer un 401 (ce n'est ni un 304 ni une coupure réseau) avant que l'auth
  // tente son rafraîchissement.
  dio.interceptors.add(AuthInterceptor(auth, baseUrl));
  dio.interceptors.add(ETagCacheInterceptor(store));
  return NewsApiClient(dio: dio);
});
