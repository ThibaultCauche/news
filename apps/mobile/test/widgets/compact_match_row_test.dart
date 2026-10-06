import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/widgets/compact_match_row.dart";
import "package:mobile/widgets/match_context.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

CompetitionRefDto _competition({String name = "Group C", String? tournament = "Champions 2026", String? game}) => CompetitionRefDto(
  (c) => c
    ..id = "c1"
    ..name = name
    ..tournamentName = tournament
    ..game = game,
);

EventSummaryDto _event({String status = "scheduled", int? a, int? b, CompetitionRefDto? competition}) => EventSummaryDto(
  (e) => e
    ..id = "e1"
    ..kind = "match"
    ..name = "G2 vs PRX"
    ..status = status
    ..startsAt = DateTime(2026, 10, 7, 17, 30).toUtc().toIso8601String()
    ..bestOf = 3
    ..importance = 1
    ..competition.replace(competition ?? _competition())
    ..participants.addAll([
      EventParticipantDto((p) => p
        ..entityId = "g2"
        ..name = "G2 Esports"
        ..shortName = "G2"
        ..score = a
        ..isWinner = a != null && b != null ? a > b : null),
      EventParticipantDto((p) => p
        ..entityId = "prx"
        ..name = "Paper Rex"
        ..shortName = "PRX"
        ..score = b
        ..isWinner = a != null && b != null ? b > a : null),
    ]),
);

Future<void> _pump(WidgetTester tester, EventSummaryDto event, {bool hidden = false}) => tester.pumpWidget(
  ProviderScope(
    overrides: [overrideSignedInForTest(), overrideFollowsRecording(const [], <String>[])],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: CompactMatchRow(event: event, scoresHidden: hidden, followedEntityIds: const {"g2"})),
    ),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  test("ligne de contexte : tournoi puis étape en français, l'étape seule sans tournoi (J22, #A1)", () {
    expect(matchContextLabel(_competition()), "Champions 2026 · Groupe C");
    expect(matchContextLabel(_competition(tournament: null)), "Groupe C");
    expect(matchContextLabel(_competition(name: "Champions 2026", tournament: "Champions 2026")), "Champions 2026");
  });

  test("regroupement par compétition, dans l'ordre du premier match", () {
    final groups = groupByCompetition([
      _event(competition: _competition(name: "Group A")),
      _event(competition: _competition(name: "Group B")),
      _event(competition: _competition(name: "Group A")),
    ]);
    expect(groups.map((g) => g.$2.length), [2, 1]);
  });

  testWidgets("match à venir : heure, deux équipes, cloche, 64 px de haut", (tester) async {
    await _pump(tester, _event());
    expect(find.text("17:30"), findsOneWidget);
    expect(find.text("G2"), findsOneWidget);
    expect(find.text("PRX"), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(CompactMatchRow)).height, CompactMatchRow.height);
  });

  testWidgets("match en direct : « DIRECT » et scores, sans cloche", (tester) async {
    await _pump(tester, _event(status: "live", a: 1, b: 0));
    expect(find.text("DIRECT"), findsOneWidget);
    expect(find.text("1"), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox()); // arrête le point qui respire
  });

  testWidgets("match terminé : scores visibles, nets", (tester) async {
    await _pump(tester, _event(status: "finished", a: 2, b: 1));
    expect(find.text("TERMINÉ"), findsOneWidget);
    expect(find.text("2"), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets("sans spoil : le score d'un match terminé est flouté (J22)", (tester) async {
    await _pump(tester, _event(status: "finished", a: 2, b: 1), hidden: true);
    expect(find.byType(ImageFiltered), findsWidgets);
  });
}
