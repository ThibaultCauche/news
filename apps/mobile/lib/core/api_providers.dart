import "package:dio/dio.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "cache/app_database.dart";
import "cache/cache_store.dart";
import "cache/etag_cache_interceptor.dart";

/// En dev, l'API tourne sur la machine hôte : sur Android, `adb reverse
/// tcp:3000 tcp:3000` fait pointer `localhost` de l'appareil (émulateur ou
/// téléphone en USB) vers `localhost` de l'hôte, comme sur les autres cibles.
String resolveApiBaseUrl() => "http://localhost:3000";

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
  final dio = Dio(BaseOptions(baseUrl: resolveApiBaseUrl()));
  dio.interceptors.add(ETagCacheInterceptor(store));
  return NewsApiClient(dio: dio);
});
