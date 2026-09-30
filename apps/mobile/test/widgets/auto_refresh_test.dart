import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/auto_refresh.dart";
import "package:mobile/core/clock.dart";
import "package:mobile/core/navigation.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/agenda/agenda_screen.dart";
import "package:mobile/features/home/home_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../settings_test_helpers.dart";

// Date du jour pilotable à la main, à la place de `DateTime.now()`.
class _FakeToday extends TodayNotifier {
  _FakeToday(this.initial);
  final DateTime initial;

  @override
  DateTime build() => initial;

  void set(DateTime day) => state = day;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  test("TodayNotifier.sync ne bouge pas tant que le jour est le même", () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final before = container.read(todayProvider);
    container.read(todayProvider.notifier).sync();
    expect(container.read(todayProvider), before);
    expect(before, dateOnly(DateTime.now()));
  });

  testWidgets("l'Agenda reprend le nouveau jour quand la date change (app laissée ouverte la nuit)", (tester) async {
    final today = _FakeToday(DateTime(2026, 9, 29));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(() => today),
          agendaProvider.overrideWith((ref, query) async => AgendaResponseDto((b) => b..sourceUpdatedAt = "2026-09-29T00:00:00Z")),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideCompactEventCardsWith(false),
          await overrideAuthStoreForTest(),
        ],
        child: const MaterialApp(home: Scaffold(body: AgendaScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Semaine du lundi 28 au dimanche 4 : les deux jours y sont, la sélection est sur le 29.
    expect(find.text("29"), findsWidgets);
    final container = ProviderScope.containerOf(tester.element(find.byType(AgendaScreen)));
    (container.read(todayProvider.notifier) as _FakeToday).set(DateTime(2026, 10, 7)); // nouvelle semaine
    await tester.pumpAndSettle();

    // La semaine affichée est celle du 5 au 11 octobre, sélection sur le 7.
    expect(find.text("5"), findsOneWidget);
    expect(find.text("11"), findsOneWidget);
    expect(find.text("28"), findsNothing);
  });

  HomeResponseDto home0() => HomeResponseDto((b) => b..sourceUpdatedAt = "2026-09-29T00:00:00Z");

  Future<int Function()> pumpWithRefresh(WidgetTester tester) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith((ref) async {
            loads++;
            return home0();
          }),
        ],
        child: MaterialApp(
          home: AutoRefresh(
            child: Consumer(builder: (context, ref, _) => Text(ref.watch(homeProvider).hasValue ? "prêt" : "…")),
          ),
        ),
      ),
    );
    await tester.pump();
    return () => loads;
  }

  testWidgets("recharge l'Accueil chaque minute, sans repasser par un spinner", (tester) async {
    final loads = await pumpWithRefresh(tester);
    expect(loads(), 1);

    await tester.pump(autoRefreshInterval + const Duration(seconds: 1));
    await tester.pump();
    expect(loads(), 2);
    expect(find.text("prêt"), findsOneWidget); // l'ancien contenu reste affiché pendant le rechargement

    await tester.pumpWidget(const SizedBox()); // arrête la minuterie
  });

  testWidgets("retour au premier plan : tout est rechargé ; en arrière-plan, plus de minuterie", (tester) async {
    final loads = await pumpWithRefresh(tester);
    expect(loads(), 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(autoRefreshInterval * 3);
    expect(loads(), 1); // rien ne tourne en arrière-plan

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(loads(), 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("changer d'onglet recharge les données visibles", (tester) async {
    final loads = await pumpWithRefresh(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(AutoRefresh)));

    container.read(tabIndexProvider.notifier).select(3);
    await tester.pump();
    await tester.pump();
    expect(loads(), 2);

    await tester.pumpWidget(const SizedBox());
  });
}
