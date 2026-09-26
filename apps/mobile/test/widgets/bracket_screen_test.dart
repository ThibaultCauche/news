import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_painter.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/follows/follows_provider.dart";
import "package:news_api_client/news_api_client.dart";

CompetitionChildDto _child(String id, String name) => CompetitionChildDto((b) => b
  ..id = id
  ..name = name
  ..kind = "tournament");

CompetitionResponseDto _competition({required String id, required String name, List<CompetitionChildDto> children = const [], List<CompetitionStandingDto> standings = const []}) {
  return CompetitionResponseDto((b) => b
    ..id = id
    ..name = name
    ..kind = "tournament"
    ..sourceUpdatedAt = "2026-09-26T00:00:00Z"
    ..children.addAll(children)
    ..standings.addAll(standings));
}

CompetitionStandingDto _standing({required String entityId, required String name, required int rank, required bool qualified}) {
  return CompetitionStandingDto((b) => b
    ..entityId = entityId
    ..entityName = name
    ..rank = rank
    ..wins = 5 - rank
    ..losses = rank - 1
    ..qualified = qualified);
}

BracketParticipantDto _participant({required String entityId, required String name, bool? isWinner}) {
  return BracketParticipantDto((b) => b
    ..entityId = entityId
    ..name = name
    ..shortName = name
    ..isWinner = isWinner);
}

BracketNodeDto _node({required String eventId, required String name, String status = "scheduled", num round = 1, List<BracketParticipantDto> participants = const []}) {
  return BracketNodeDto((b) => b
    ..eventId = eventId
    ..name = name
    ..status = status
    ..round = round
    ..participants.addAll(participants));
}

BracketLinkDto _link({required String from, required String to, required String outcome}) {
  return BracketLinkDto((b) => b
    ..fromEventId = from
    ..toEventId = to
    ..outcome = outcome
    ..slot = 0);
}

Future<void> _pump(WidgetTester tester) {
  final qf1 = _node(
    eventId: "qf1",
    name: "Upper Bracket Quarterfinal 1",
    status: "finished",
    round: 2,
    participants: [_participant(entityId: "g2", name: "G2", isWinner: true), _participant(entityId: "th", name: "TH", isWinner: false)],
  );
  final finalNode = _node(eventId: "final", name: "Grand Final", round: 0);
  final lower1 = _node(eventId: "lower1", name: "Lower Bracket Round 1 Match 1", round: 3);
  final bracket = BracketResponseDto((b) => b
    ..format = "double_elim"
    ..sourceUpdatedAt = "2026-09-26T00:00:00Z"
    ..nodes.addAll([qf1, finalNode, lower1])
    ..links.addAll([_link(from: "qf1", to: "final", outcome: "winner"), _link(from: "qf1", to: "lower1", outcome: "loser")]));

  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        competitionDetailProvider("champions").overrideWith((ref) async => _competition(
              id: "champions",
              name: "Champions",
              children: [_child("groupA", "Group A"), _child("playoffs", "Playoffs")],
            )),
        competitionDetailProvider("groupA").overrideWith((ref) async => _competition(
              id: "groupA",
              name: "Group A",
              standings: [
                _standing(entityId: "g2", name: "G2", rank: 1, qualified: true),
                _standing(entityId: "th", name: "TH", rank: 2, qualified: true),
                _standing(entityId: "t1", name: "T1", rank: 3, qualified: false),
                _standing(entityId: "kru", name: "KRÜ", rank: 4, qualified: false),
              ],
            )),
        bracketProvider("playoffs").overrideWith((ref) async => bracket),
        followsProvider.overrideWith((ref) async => [
              FollowStateDto((b) => b
                ..id = "sub-g2"
                ..targetType = "entity"
                ..targetId = "g2"
                ..level = "all"
                ..notifyReminder = true
                ..notifyStart = true
                ..notifyResult = true
                ..name = "G2"),
            ]),
      ],
      child: const MaterialApp(
        theme: null,
        home: BracketScreen(competitionId: "champions", title: "Champions", subtitle: "Phase de groupes"),
      ),
    ),
  );
}

void main() {
  testWidgets("onglet Groupes : classement trié, trait entre qualifiés et éliminés", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text("G2"), findsOneWidget);
    expect(find.text("KRÜ"), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets("onglet Phase finale : l'arbre radial met en or le match du suivi (G2)", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Phase finale"));
    await tester.pumpAndSettle();

    final customPaint = tester.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter),
    );
    final painter = customPaint.painter as BracketPainter;
    expect(painter.highlightedEventIds, {"qf1"});
    // La finale (TBD) est dans l'arbre mais pas encore en or : G2 n'y a pas
    // encore de participation confirmée.
    expect(painter.nodes.map((n) => n.eventId), containsAll(["qf1", "final"]));
    // Le tableau bas (repêchage) ne fait pas partie de l'arbre radial.
    expect(painter.nodes.map((n) => n.eventId), isNot(contains("lower1")));
  });

  testWidgets("onglet Repêchage : match pas encore joué affiché comme « Perdant de G2 vs TH »", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Repêchage"));
    await tester.pumpAndSettle();

    expect(find.textContaining("Perdant de G2 vs TH"), findsOneWidget);
  });
}
