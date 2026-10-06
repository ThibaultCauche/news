import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/core/api_providers.dart";
import "package:mobile/core/navigation.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/widgets/match_countdown.dart";
import "package:mobile/features/home/home_screen.dart";
import "package:mobile/features/profile/community_providers.dart";
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

HomeResponseDto _home({
  List<GrandFinalDto> grandFinals = const [],
  List<EventSummaryDto> live = const [],
  List<EventSummaryDto> upcoming = const [],
  List<EventSummaryDto> todayFollowed = const [],
  List<MajorCompetitionDto> majors = const [],
}) => HomeResponseDto(
      (b) => b
        ..sourceUpdatedAt = "2026-10-18T10:00:00.000Z"
        ..liveNow.addAll(live)
        ..upcoming.addAll(upcoming)
        ..grandFinals.addAll(grandFinals)
        ..todayFollowed.addAll(todayFollowed)
        ..majors.addAll(majors),
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
  final authStore = await tester.runAsync(() async => await overrideAuthStoreForTest());
  final container = ProviderContainer(overrides: [
        overrideSignedInForTest(),
        authStore,
        // Pas de vrai client : la progression des tutos échoue en silence (hors ligne), sans base ni réseau.
        apiClientProvider.overrideWith((ref) => throw UnimplementedError("pas de réseau en test")),
        profileProvider.overrideWith((ref) async => null),
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
    expect(find.text("Groupe B"), findsOneWidget); // le BO n'apparaît plus une fois le score affiché
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

    // La grande finale est la seule grande carte : son état spécial (J22).
    expect(find.text("À suivre"), findsOneWidget);
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

  testWidgets("matchs en direct en plus du premier : pastilles avec score (J22)", (tester) async {
    await _pump(
      tester,
      _home(live: [_match("l1", "live", "VIT", "LOUD", scoreA: 1, scoreB: 0), _match("l2", "live", "NRG", "KC", scoreA: 0, scoreB: 2)]),
    );
    // Le premier est sur la grande carte, le second en pastille.
    expect(find.byType(LivePill), findsOneWidget);
    expect(find.descendant(of: find.byType(LivePill), matching: find.text("2")), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("aujourd'hui dans tes suivis : lignes compactes groupées, rien d'affiché sans match (J22)", (tester) async {
    await _pump(tester, _home(todayFollowed: [_match("t1", "scheduled", "FNC", "G2", startsAt: _todayAt(23, 59))], upcoming: [_match("n", "scheduled", "AAA", "BBB", startsAt: _todayAt(23, 58))]));
    expect(find.text("Aujourd'hui dans tes suivis"), findsOneWidget);
    expect(find.text("FNC"), findsOneWidget);
    expect(find.text("GROUPE B"), findsOneWidget);
  });

  testWidgets("aucune section vide : sans suivi du jour ni grand rendez-vous, rien n'est affiché (J22)", (tester) async {
    await _pump(tester, _home());
    expect(find.text("Aujourd'hui dans tes suivis"), findsNothing);
    expect(find.text("Les grands rendez-vous"), findsNothing);
  });

  testWidgets("grands rendez-vous : mini-cartes de tournois, « En cours » ou date (J22)", (tester) async {
    await _pump(
      tester,
      _home(majors: [
        MajorCompetitionDto((m) => m..id = "c1"..name = "Champions 2026"..live = true),
        MajorCompetitionDto((m) => m..id = "c2"..name = "Masters Toronto"..live = false..startsAt = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String()),
      ]),
    );
    expect(find.text("Les grands rendez-vous"), findsOneWidget);
    expect(find.text("Champions 2026"), findsOneWidget);
    expect(find.text("En cours"), findsOneWidget);
    expect(find.text("Masters Toronto"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("résultats d'hier : section repliée, qui s'ouvre au toucher (J22)", (tester) async {
    final n = DateTime.now();
    final yesterday = DateTime(n.year, n.month, n.day - 1, 20);
    await _pump(tester, _home(todayFollowed: [_match("y1", "finished", "FNC", "G2", scoreA: 2, scoreB: 1, startsAt: yesterday)]));
    expect(find.text("HIER · 1 RÉSULTAT"), findsOneWidget);
    expect(find.text("FNC"), findsNothing); // replié
    await tester.tap(find.text("HIER · 1 RÉSULTAT"));
    await tester.pump();
    expect(find.text("FNC"), findsOneWidget);
  });

  testWidgets("match suivi dans moins d'une heure : pastille avec compte à rebours (J22)", (tester) async {
    final soon = DateTime.now().add(const Duration(minutes: 30));
    await _pump(tester, _home(todayFollowed: [_match("s1", "scheduled", "FNC", "G2", startsAt: soon)]));
    expect(find.byType(LivePill), findsOneWidget);
    expect(find.byType(MatchCountdown), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("un match suivi dans plus d'une heure n'a pas de pastille (J22)", (tester) async {
    final later = DateTime.now().add(const Duration(hours: 3));
    await _pump(tester, _home(todayFollowed: [_match("s2", "scheduled", "FNC", "G2", startsAt: later)]));
    expect(find.byType(LivePill), findsNothing);
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
