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

// Aujourd'hui à `h`:`m` (heure locale) : seul le jour compte pour « Ensuite », pas l'heure.
DateTime _todayAt(int h, int m) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, h, m);
}

HomeResponseDto _home({List<GrandFinalDto> grandFinals = const [], List<EventSummaryDto> live = const [], List<EventSummaryDto> upcoming = const []}) => HomeResponseDto(
      (b) => b
        ..sourceUpdatedAt = "2026-10-18T10:00:00.000Z"
        ..liveNow.addAll(live)
        ..upcoming.addAll(upcoming)
        ..grandFinals.addAll(grandFinals),
    );

EventSummaryDto _match(String id, String status, String a, String b, {int? scoreA, int? scoreB, DateTime? startsAt}) => EventSummaryDto(
      (e) => e
        ..id = id
        ..kind = "match"
        ..name = "$a vs $b"
        ..status = status
        ..startsAt = (startsAt ?? DateTime.now()).toUtc().toIso8601String()
        ..bestOf = 3
        ..importance = 1
        ..competition.replace(CompetitionRefDto((c) => c
          ..id = "c"
          ..name = "Group B"))
        ..participants.addAll([
          EventParticipantDto((p) => p
            ..entityId = "$id-a"
            ..name = a
            ..shortName = a
            ..score = scoreA),
          EventParticipantDto((p) => p
            ..entityId = "$id-b"
            ..name = b
            ..shortName = b
            ..score = scoreB),
        ]),
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

  testWidgets("match en direct : carte de match commune (logos, scores) en rouge, avec « Ensuite » en dessous", (tester) async {
    await _pump(
      tester,
      _home(live: [_match("live", "live", "VIT", "LOUD", scoreA: 1, scoreB: 0)], upcoming: [_match("next", "scheduled", "FUT", "100T", startsAt: _todayAt(23, 59))]),
    );

    expect(find.text("EN DIRECT"), findsOneWidget);
    expect(find.text("VIT"), findsOneWidget);
    expect(find.text("LOUD"), findsOneWidget);
    expect(find.text("1"), findsOneWidget); // score sous le logo, comme sur toutes les cartes
    expect(find.text("Group B"), findsOneWidget); // le BO n'apparaît plus une fois le score affiché
    expect(find.text("Ensuite : FUT – 100T"), findsOneWidget);
    // Même ordre que l'API : la première équipe à gauche.
    expect(tester.getTopLeft(find.text("VIT")).dx, lessThan(tester.getTopLeft(find.text("LOUD")).dx));

    await tester.pumpWidget(const SizedBox()); // arrête l'animation du point
  });

  testWidgets("le match suivant est demain : pas de ligne « Ensuite » (J10)", (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await _pump(
      tester,
      _home(
        live: [_match("live", "live", "VIT", "LOUD", scoreA: 1, scoreB: 0)],
        upcoming: [_match("next", "scheduled", "TYLOO", "TL", startsAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12))],
      ),
    );
    expect(find.text("EN DIRECT"), findsOneWidget);
    expect(find.textContaining("Ensuite"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("match en direct sans match ensuite : pas de ligne « Ensuite »", (tester) async {
    await _pump(tester, _home(live: [_match("live", "live", "VIT", "LOUD", scoreA: 0, scoreB: 0)]));
    expect(find.textContaining("Ensuite"), findsNothing);
    await tester.pumpWidget(const SizedBox());
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
