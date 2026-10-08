import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/competitions/competitions_data.dart" show catalogProvider;
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:mobile/features/politics/election_widgets.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

ElectionListDto _list(int panel, String label, int votes, double pct, int seats, {String? head}) => ElectionListDto((b) => b
  ..panel = panel
  ..label = label
  ..head = head
  ..votes = votes
  ..pctExpressed = pct
  ..elected = false
  ..seatsCouncil = seats
  ..seatsCommunity = 0);

ElectionResultDto _result({bool national = false}) => ElectionResultDto((b) => b
  ..level = national ? ElectionResultDtoLevelEnum.national : ElectionResultDtoLevelEnum.commune
  ..candidates = national
  ..bureaux = national ? null : (BureauxDtoBuilder()
    ..counted = 9
    ..total = 10)
  ..territoryCode = "01249"
  ..territoryName = "Miribel"
  ..department = "Ain"
  ..registered = 7293
  ..voters = 3920
  ..turnoutPct = 53.75
  ..blank = 41
  ..nulls = 27
  ..expressed = 3852
  ..totalSeats = 33
  ..majoritySeats = 17
  ..complete = true
  ..sourceUrl = "https://static.data.gouv.fr/x.csv"
  ..lists.addAll([_list(3, "MIRIBEL AU COEUR", 1535, 39.85, 24, head: "Sylvie VIRICEL"), _list(2, "MIRIBEL C'EST VOUS", 1466, 38.06, 6), _list(4, "Miribel, responsable et ambitieuse", 472, 12.25, 3)]));

EventDetailResponseDto _event(ElectionDto election) => EventDetailResponseDto((b) => b
  ..id = "res-1"
  ..kind = "election_result"
  ..name = "Miribel"
  ..status = "finished"
  ..importance = 0
  ..sourceUpdatedAt = "2026-03-22T21:00:00Z"
  ..result = JsonObject(<String, dynamic>{})
  ..competition.replace(CompetitionRefDto((c) => c
    ..id = "elec-1"
    ..name = "Municipales 2026 · 2ᵈ tour"))
  ..context.replace(EventContextDto((c) => c))
  ..election.replace(election));

ElectionDto _election({required bool embargoed}) => ElectionDto((b) => b
  ..electionId = "municipales-2026-t2"
  ..name = "Municipales 2026 · 2ᵈ tour"
  ..round = 2
  ..date = "2026-03-22"
  ..embargoed = embargoed
  ..liftsAt = "2026-03-22T19:00:00.000Z"
  ..result = embargoed ? null : _result().toBuilder());

Future<void> _pumpEvent(WidgetTester tester, EventDetailResponseDto event) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [eventProvider("res-1").overrideWith((ref) async => event), overrideFollowsWith(const [])],
    child: const MaterialApp(home: NextMatchScreen(eventId: "res-1")),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting("fr_FR"));

  testWidgets("la soirée électorale d'une commune : participation, sièges, voix par liste et fichier officiel", (tester) async {
    await _pumpEvent(tester, _event(_election(embargoed: false)));
    expect(find.text("Miribel"), findsWidgets);
    expect(find.text("RÉSULTATS DÉFINITIFS"), findsOneWidget);
    expect(find.text("Participation"), findsOneWidget);
    expect(find.text("53,8 %"), findsOneWidget);
    expect(find.textContaining("3 920 votants sur 7 293 inscrits"), findsOneWidget);
    expect(find.text("SIÈGES AU CONSEIL · 33"), findsOneWidget);
    expect(find.text("Majorité : 17 sièges (trait pointillé)"), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("Sièges au conseil")), findsOneWidget);
    expect(find.text("MIRIBEL AU COEUR"), findsOneWidget);
    expect(find.text("39,9 %"), findsOneWidget);
    expect(find.textContaining("Tête de liste : Sylvie VIRICEL"), findsOneWidget);
    expect(find.textContaining("24 sièges"), findsOneWidget);
    expect(find.textContaining("Fichier officiel"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });

  testWidgets("pendant le dépouillement, la soirée électorale montre les bureaux dépouillés", (tester) async {
    final running = ElectionDto((b) => b
      ..electionId = "municipales-2026-t2"
      ..name = "Municipales 2026 · 2ᵈ tour"
      ..round = 2
      ..date = "2026-03-22"
      ..embargoed = false
      ..liftsAt = "2026-03-22T19:00:00.000Z"
      ..result = _result().rebuild((r) => r..complete = false).toBuilder());
    await _pumpEvent(tester, _event(running));
    expect(find.text("DÉPOUILLEMENT EN COURS"), findsOneWidget);
    expect(find.text("Bureaux dépouillés"), findsOneWidget);
    expect(find.text("9 bureaux sur 10"), findsOneWidget);
  });

  testWidgets("une fois le résultat définitif, les bureaux ne sont plus affichés", (tester) async {
    await _pumpEvent(tester, _event(_election(embargoed: false)));
    expect(find.text("Bureaux dépouillés"), findsNothing);
  });

  testWidgets("avant 20 h le jour du scrutin, l'écran n'affiche qu'un cadenas, aucune liste ni aucun chiffre", (tester) async {
    await _pumpEvent(tester, _event(_election(embargoed: true)));
    expect(find.text("Résultats à 20 h"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.textContaining("article L52-2"), findsOneWidget);
    expect(find.text("MIRIBEL AU COEUR"), findsNothing);
    expect(find.textContaining("Participation"), findsNothing);
    expect(find.textContaining("%"), findsNothing);
  });

  testWidgets("la page d'un scrutin sans jeu de données annonce l'attente de la publication officielle", (tester) async {
    final competition = CompetitionResponseDto((b) => b
      ..id = "elec-2"
      ..name = "Présidentielle 2027 · 1ᵉʳ tour"
      ..kind = "election"
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
      ..election.replace(ElectionOverviewDto((e) => e
        ..electionId = "presidentielle-2027-t1"
        ..name = "Présidentielle 2027"
        ..type = ElectionOverviewDtoTypeEnum.presidentielle
        ..round = 1
        ..date = "2027-04-18"
        ..embargoed = false
        ..liftsAt = "2099-04-18T18:00:00.000Z"
        ..hasResults = false)));
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("elec-2").overrideWith((ref) async => competition), overrideFollowsWith(const []), catalogProvider.overrideWith((ref) async => CatalogDto((b) => b))],
      child: const MaterialApp(home: ElectionScreen(competitionId: "elec-2")),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Présidentielle 2027"), findsOneWidget);
    expect(find.text("1ᵉʳ tour · dimanche 18 avril 2027"), findsOneWidget);
    expect(find.text("Résultats le soir du scrutin"), findsOneWidget);
    expect(find.textContaining("dès leur publication officielle"), findsOneWidget);
    expect(find.textContaining("ni pronostic"), findsOneWidget);
  });

  testWidgets("la présidentielle montre la France entière puis les départements, des candidats sans sièges", (tester) async {
    final national = _result(national: true).rebuild((r) => r
      ..territoryName = "France entière"
      ..totalSeats = 0
      ..majoritySeats = null
      ..lists.replace([_list(3, "Emmanuel MACRON", 9783058, 27.85, 0), _list(5, "Marine LE PEN", 8133828, 23.15, 0)]));
    final competition = CompetitionResponseDto((b) => b
      ..id = "elec-4"
      ..name = "Présidentielle 2027 · 1ᵉʳ tour"
      ..kind = "election"
      ..sourceUpdatedAt = "2027-04-18T20:00:00Z"
      ..election.replace(ElectionOverviewDto((e) => e
        ..electionId = "presidentielle-2027-t1"
        ..name = "Présidentielle 2027"
        ..type = ElectionOverviewDtoTypeEnum.presidentielle
        ..round = 1
        ..date = "2027-04-18"
        ..embargoed = false
        ..liftsAt = "2027-04-18T18:00:00.000Z"
        ..hasResults = true
        ..national = national.toBuilder()
        ..territories.add(ElectionTerritoryDto((t) => t
          ..eventId = "dep-1"
          ..level = ElectionTerritoryDtoLevelEnum.department
          ..name = "Ain"
          ..department = "Ain"
          ..registered = 438109
          ..turnoutPct = 77.74
          ..leaderLabel = "Emmanuel MACRON"
          ..leaderPct = 27.69
          ..complete = true)))));
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("elec-4").overrideWith((ref) async => competition), overrideFollowsWith(const []), catalogProvider.overrideWith((ref) async => CatalogDto((b) => b))],
      child: const MaterialApp(home: ElectionScreen(competitionId: "elec-4")),
    ));
    await tester.pumpAndSettle();
    expect(find.text("FRANCE ENTIÈRE"), findsOneWidget);
    expect(find.text("Emmanuel MACRON"), findsWidgets);
    expect(find.text("27,9 %"), findsOneWidget);
    expect(find.textContaining("Candidats classés par nombre de voix"), findsOneWidget);
    expect(find.text("LES DÉPARTEMENTS"), findsOneWidget);
    expect(find.textContaining("Participation 77,7 % · Emmanuel MACRON 27,7 %"), findsOneWidget);
    // Des candidats : ni sièges ni tête de liste.
    expect(find.textContaining("siège"), findsNothing);
    expect(find.textContaining("Tête de liste"), findsNothing);
  });

  testWidgets("la page d'un scrutin passé liste les grandes villes avec participation et liste en tête", (tester) async {
    final competition = CompetitionResponseDto((b) => b
      ..id = "elec-3"
      ..name = "Municipales 2026 · 2ᵈ tour"
      ..kind = "election"
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
      ..election.replace(ElectionOverviewDto((e) => e
        ..electionId = "municipales-2026-t2"
        ..name = "Municipales 2026"
        ..type = ElectionOverviewDtoTypeEnum.municipales
        ..round = 2
        ..date = "2026-03-22"
        ..embargoed = false
        ..liftsAt = "2026-03-22T19:00:00.000Z"
        ..hasResults = true
        ..territories.add(ElectionTerritoryDto((t) => t
          ..eventId = "res-1"
          ..level = ElectionTerritoryDtoLevelEnum.commune
          ..name = "Miribel"
          ..department = "Ain"
          ..registered = 7293
          ..turnoutPct = 53.75
          ..leaderLabel = "MIRIBEL AU COEUR"
          ..leaderPct = 39.85
          ..complete = true)))));
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("elec-3").overrideWith((ref) async => competition), overrideFollowsWith(const []), catalogProvider.overrideWith((ref) async => CatalogDto((b) => b))],
      child: const MaterialApp(home: ElectionScreen(competitionId: "elec-3")),
    ));
    await tester.pumpAndSettle();
    expect(find.text("LES GRANDES VILLES"), findsOneWidget);
    expect(find.text("Miribel"), findsOneWidget);
    expect(find.textContaining("Participation 53,8 % · MIRIBEL AU COEUR 39,9 %"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });
}
