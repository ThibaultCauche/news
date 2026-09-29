import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/navigation.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/home/home_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";
import "../settings_test_helpers.dart";

EventSummaryDto _final({bool withTeams = true}) => EventSummaryDto(
      (b) => b
        ..id = "final-1"
        ..kind = "match"
        ..name = "Grand Final"
        ..status = "scheduled"
        ..startsAt = "2026-10-18T17:00:00.000Z"
        ..bestOf = 5
        ..importance = 3
        ..competition.replace(CompetitionRefDto((c) => c
          ..id = "playoffs"
          ..name = "Champions 2026 · Playoffs"))
        ..participants.addAll(withTeams
            ? [
                EventParticipantDto((p) => p
                  ..entityId = "g2"
                  ..name = "G2 Esports"
                  ..shortName = "G2"),
                EventParticipantDto((p) => p
                  ..entityId = "prx"
                  ..name = "Paper Rex"
                  ..shortName = "PRX"),
              ]
            : <EventParticipantDto>[]),
    );

HomeResponseDto _home({List<GrandFinalDto> grandFinals = const []}) => HomeResponseDto(
      (b) => b
        ..sourceUpdatedAt = "2026-10-18T10:00:00.000Z"
        ..grandFinals.addAll(grandFinals),
    );

Future<ProviderContainer> _pump(WidgetTester tester, HomeResponseDto home, {List<String>? calls}) async {
  final container = ProviderContainer(overrides: [
    homeProvider.overrideWith((ref) async => home),
    userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
      ..spoilerFree = false
      ..morningDigest = false)),
    overrideCompactEventCardsWith(false),
    overrideFollowsRecording(const [], calls ?? []),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: ThemeData.dark(), home: const Scaffold(body: HomeScreen())),
  ));
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("hors phase finale : pas de section « grands rendez-vous »", (tester) async {
    await _pump(tester, _home());
    expect(find.text("Les grands rendez-vous"), findsNothing);
  });

  testWidgets("grande finale : carte dédiée avec contexte et alerte (J10)", (tester) async {
    final calls = <String>[];
    await _pump(tester, _home(grandFinals: [GrandFinalDto((b) => b..event.replace(_final())..tournamentName = "Champions 2026"..stakes = "Le vainqueur est sacré champion. Match en [[BO5]].")]), calls: calls);

    expect(find.text("Les grands rendez-vous"), findsOneWidget);
    expect(find.text("GRANDE FINALE"), findsOneWidget);
    expect(find.text("Champions 2026"), findsOneWidget); // le tournoi, pas « Playoffs » seul
    expect(find.text("G2"), findsOneWidget);
    expect(find.text("PRX"), findsOneWidget);
    expect(find.text("POURQUOI ÇA COMPTE"), findsOneWidget);
    expect(find.textContaining("sacré champion", findRichText: true), findsOneWidget);

    await tester.tap(find.text("M'alerter au début du match"));
    await tester.pump();
    expect(calls, ["follow event final-1"]);
    expect(find.text("Alerte activée"), findsOneWidget);
  });

  testWidgets("grande finale sans adversaires connus : « Adversaires à déterminer »", (tester) async {
    await _pump(tester, _home(grandFinals: [GrandFinalDto((b) => b..event.replace(_final(withTeams: false))..tournamentName = "Champions 2026")]));
    expect(find.text("Adversaires à déterminer"), findsOneWidget);
    expect(find.text("POURQUOI ÇA COMPTE"), findsNothing);
  });

  testWidgets("l'icône de recherche ouvre l'onglet Compétitions et demande le focus (J10)", (tester) async {
    final container = await _pump(tester, _home());
    expect(container.read(tabIndexProvider), 0);
    final focusBefore = container.read(searchFocusRequestProvider);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();

    expect(container.read(tabIndexProvider), competitionsTabIndex);
    expect(container.read(searchFocusRequestProvider), focusBefore + 1);
  });
}
