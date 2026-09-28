import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/widgets/event_card.dart";
import "package:news_api_client/news_api_client.dart";
import "../settings_test_helpers.dart";

EventSummaryDto _event({
  required String status,
  String? startsAt,
  int? scoreA,
  int? scoreB,
}) {
  return EventSummaryDto(
    (b) => b
      ..id = "evt-1"
      ..kind = "match"
      ..name = "G2 Esports vs Paper Rex"
      ..status = status
      ..startsAt = startsAt
      ..bestOf = 3
      ..importance = 3
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "comp-1"
        ..name = "Champions 2026 · Playoffs"))
      ..participants.addAll([
        EventParticipantDto((p) => p
          ..entityId = "team-a"
          ..name = "G2 Esports"
          ..shortName = "G2"
          ..score = scoreA
          ..isWinner = scoreA != null && scoreB != null ? scoreA > scoreB : null),
        EventParticipantDto((p) => p
          ..entityId = "team-b"
          ..name = "Paper Rex"
          ..shortName = "PRX"
          ..score = scoreB
          ..isWinner = scoreA != null && scoreB != null ? scoreB > scoreA : null),
      ]),
  );
}

Future<void> _pump(WidgetTester tester, EventSummaryDto event, {bool scoresHidden = false}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [overrideCompactEventCardsWith(false)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: EventCard(event: event, scoresHidden: scoresHidden)),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting("fr_FR");
  });

  testWidgets("à venir : affiche l'heure de début, pas de score", (tester) async {
    await _pump(tester, _event(status: "scheduled", startsAt: "2026-10-18T11:55:00.000Z"));
    // Diminutif ("G2"/"PRX"), pas le nom complet (docs/02 — "le plus visuel possible").
    expect(find.textContaining("G2"), findsOneWidget);
    expect(find.text("1-0"), findsNothing);
  });

  testWidgets("en direct : affiche le score par équipe sous chaque logo et le point rouge", (tester) async {
    await _pump(tester, _event(status: "live", scoreA: 1, scoreB: 0));
    expect(find.text("1"), findsOneWidget);
    expect(find.text("0"), findsOneWidget);
  });

  testWidgets("terminé : affiche le score final par équipe sous chaque logo", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0));
    expect(find.text("2"), findsOneWidget);
    expect(find.text("0"), findsOneWidget);
  });

  testWidgets("terminé, sans spoil activé : masque le score (écran 15, J6)", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0), scoresHidden: true);
    expect(find.text("2"), findsNothing);
    expect(find.text("0"), findsNothing);
    // "VS" toujours affiché entre les deux logos, quel que soit le statut.
    expect(find.text("VS"), findsOneWidget);
  });

  testWidgets("reporté : affiche le statut, pas d'heure ni de score", (tester) async {
    await _pump(tester, _event(status: "postponed"));
    expect(find.text("Reporté"), findsOneWidget);
  });
}
