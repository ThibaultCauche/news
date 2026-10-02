import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/cache/cache_store.dart";
import "package:mobile/core/cache/etag_cache_interceptor.dart";
import "package:mobile/core/navigation.dart";
import "package:mobile/core/offline.dart";
import "package:mobile/features/account/auth_screen.dart";
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:mobile/widgets/async_view.dart";
import "package:mobile/widgets/offline_banner.dart";

class _MemoryStore implements CacheStore {
  final entries = <String, CachedEntry>{};

  @override
  Future<CachedEntry?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, {required String body, String? etag}) async {
    entries[key] = CachedEntry(body: body, etag: etag, storedAt: DateTime(2026, 10, 2, 10, 42));
  }

  @override
  Future<void> clear() async => entries.clear();
}

class _Adapter implements HttpClientAdapter {
  bool down = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (down) throw DioException.connectionError(requestOptions: options, reason: "réseau coupé");
    return ResponseBody.fromString('{"ok":true}', 200, headers: {"content-type": ["application/json"], "etag": ['"v1"']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test("repli sur le cache : hors ligne signalé avec l'heure des données, en ligne dès qu'une réponse arrive", () async {
    final events = <String>[];
    final adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: "http://api.test"))
      ..httpClientAdapter = adapter
      ..interceptors.add(ETagCacheInterceptor(_MemoryStore(), onOffline: (t) => events.add("offline ${t.hour}h${t.minute}"), onOnline: () => events.add("online")));

    await dio.get("/home");
    adapter.down = true;
    final cached = await dio.get("/home");
    adapter.down = false;
    await dio.get("/home");

    expect(cached.data, {"ok": true}, reason: "la réponse en cache est servie");
    expect(events, ["online", "offline 10h42", "online"]);
  });

  testWidgets("bandeau hors ligne : heure des données, disparaît au retour du réseau", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: OfflineBanner()))));
    expect(find.textContaining("Hors ligne"), findsNothing);

    final container = ProviderScope.containerOf(tester.element(find.byType(OfflineBanner)));
    container.read(offlineProvider.notifier).markOffline(DateTime(2026, 10, 2, 9, 5));
    await tester.pump();
    expect(find.text("Hors ligne · données de 9 h 05"), findsOneWidget);

    container.read(offlineProvider.notifier).markOnline();
    await tester.pump();
    expect(find.textContaining("Hors ligne"), findsNothing);
  });

  testWidgets("« Annuler » : la barre de message rejoue l'action inverse", (tester) async {
    var undone = 0;
    await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: scaffoldMessengerKey, home: const Scaffold(body: SizedBox())));
    showUndo("Suivi retiré.", () async => undone++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // fin de l'entrée de la barre
    expect(find.text("Suivi retiré."), findsOneWidget);
    await tester.tap(find.text("Annuler"));
    expect(undone, 1);
  });

  testWidgets("« Annuler » : la barre se ferme toute seule après 5 s (une action la gardait ouverte)", (tester) async {
    await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: scaffoldMessengerKey, home: const Scaffold(body: SizedBox())));
    showUndo("Utilisateur bloqué.", () async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Utilisateur bloqué."), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Utilisateur bloqué."), findsNothing);
  });

  test("agenda : titre des deux équipes, compétition en description, deux heures", () {
    final start = DateTime(2026, 10, 3, 12);
    final event = calendarEventFor(teams: ["KC", "NS"], competition: "Champions 2026", start: start);
    expect(event.title, "KC – NS");
    expect(event.description, "Champions 2026");
    expect(event.endDate.difference(event.startDate), const Duration(hours: 2));
  });

  // Grande police et petit écran (J18) : aucune mise en page ne doit déborder (un débordement fait
  // échouer le test).
  for (final (name, widget) in <(String, Widget)>[
    ("connexion", const AuthScreen()),
    ("erreur de chargement", Scaffold(body: ErrorState(message: "Impossible de charger la saison.", onRetry: () {}))),
    ("skeleton", const Scaffold(body: SkeletonCards())),
  ]) {
    testWidgets("$name : lisible avec une grande police sur un écran de 320 px", (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.2)),
            child: MaterialApp(home: widget),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
