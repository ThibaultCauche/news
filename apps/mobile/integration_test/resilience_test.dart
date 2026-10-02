// Rejoue sur appareil le protocole de panne du J15/J18 : API lente (skeleton), puis API coupée
// (erreur + « Réessayer »), puis rétablie. À lancer avec l'API locale et `adb reverse tcp:3000 tcp:3000` :
//   flutter test integration_test/resilience_test.dart -d <appareil>
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:dio/io.dart";
import "package:drift/native.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/api_providers.dart";
import "package:mobile/core/auth/auth_store.dart";
import "package:mobile/core/cache/app_database.dart";
import "package:mobile/core/offline.dart";
import "package:mobile/features/onboarding/onboarding_flow.dart" show suggestedTeamsProvider;
import "package:mobile/main.dart";
import "package:mobile/widgets/async_view.dart";
import "package:shared_preferences/shared_preferences.dart";

enum Mode { ok, slow, down }

/// Vraie API derrière, avec une panne ou un ralentissement à la demande.
class FlakyAdapter implements HttpClientAdapter {
  Mode mode = Mode.ok;
  final _real = IOHttpClientAdapter();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (mode == Mode.down) throw DioException.connectionError(requestOptions: options, reason: "panne simulée");
    if (mode == Mode.slow) await Future<void>.delayed(const Duration(seconds: 3));
    return _real.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _real.close(force: force);
}

Future<void> pumpUntil(WidgetTester tester, String what, bool Function() done, {Duration timeout = const Duration(seconds: 30), Object? Function()? debug}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(20).join(" | ");
      fail("« $what » non atteint en ${timeout.inSeconds} s ; skeletons : ${find.byType(Skeleton).evaluate().length} ; textes : $texts ; état : ${debug?.call()}");
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<(FlakyAdapter, ProviderContainer)> launch(WidgetTester tester, {required bool onboardingSeen, required Mode mode}) async {
  await initializeDateFormatting("fr_FR");
  SharedPreferences.setMockInitialValues({if (onboardingSeen) "onboarding.seen": true});
  final adapter = FlakyAdapter()..mode = mode;
  await tester.pumpWidget(
    ProviderScope(
      retry: appProviderRetry,
      overrides: [
        authStoreProvider.overrideWithValue(AuthStore(await SharedPreferences.getInstance())),
        appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
        httpClientAdapterOverrideProvider.overrideWithValue(adapter),
      ],
      child: const NewsRoot(),
    ),
  );
  return (adapter, ProviderScope.containerOf(tester.element(find.byType(MaterialApp))));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("API lente : l'Accueil montre des skeletons, jamais un spinner, puis son contenu", (tester) async {
    await launch(tester, onboardingSeen: true, mode: Mode.slow);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await pumpUntil(tester, "l'Accueil a fini de charger", () => find.byType(Skeleton).evaluate().isEmpty);
  });

  testWidgets("API coupée : erreur en français avec « Réessayer » ; rétablie : le bouton recharge", (tester) async {
    final (adapter, container) = await launch(tester, onboardingSeen: false, mode: Mode.slow);
    // Onboarding : la 2e page charge des suggestions d'équipes (API lente : skeletons).
    await tester.tap(find.text("Continuer"));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Skeleton), findsWidgets);
    await pumpUntil(tester, "suggestions chargées", () => find.byType(Skeleton).evaluate().isEmpty);

    // Panne avec un cache : la réponse en cache est servie et l'appli se déclare hors ligne
    // (c'est ce qui affiche le bandeau « Hors ligne » dans l'appli).
    adapter.mode = Mode.down;
    container.invalidate(suggestedTeamsProvider);
    await pumpUntil(tester, "hors ligne signalé", () => container.read(offlineProvider) != null);
    await pumpUntil(tester, "chargement depuis le cache terminé", () => !container.read(suggestedTeamsProvider).isLoading);
    expect(find.text("Réessayer"), findsNothing);

    // Panne sans cache : l'erreur s'affiche avec « Réessayer ».
    await container.read(cacheStoreProvider).clear();
    container.invalidate(suggestedTeamsProvider);
    await pumpUntil(tester, "erreur affichée", () => find.text("Réessayer").evaluate().isNotEmpty, debug: () => container.read(suggestedTeamsProvider));
    expect(find.textContaining("Impossible de charger les suggestions."), findsOneWidget);
    expect(find.textContaining("Dio"), findsNothing);
    expect(find.textContaining("Exception"), findsNothing);

    // API rétablie : un appui sur « Réessayer » recharge.
    adapter.mode = Mode.ok;
    await tester.tap(find.text("Réessayer"));
    await pumpUntil(tester, "erreur disparue", () => find.text("Réessayer").evaluate().isEmpty);
    expect(find.byType(ErrorState), findsNothing);
    expect(container.read(offlineProvider), isNull, reason: "une vraie réponse remet l'appli en ligne");
  });
}
