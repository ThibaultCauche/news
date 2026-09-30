import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_painter.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

CompetitionChildDto _child(String id, String name) => CompetitionChildDto((b) => b
  ..id = id
  ..name = name
  ..kind = "tournament");

// Détail du match "g-open1" (Ouverture 1 de la poule) : sert à vérifier
// qu'un tap sur sa case dans `GroupBracketTree` ouvre bien `NextMatchScreen`.
EventDetailResponseDto _detailEvent() {
  final b = EventDetailResponseDtoBuilder()
    ..id = "g-open1"
    ..kind = "match"
    ..name = "Opening Match 1"
    ..status = "finished"
    ..importance = 1
    ..sourceUpdatedAt = "2026-09-26T00:00:00Z"
    ..result = JsonObject(<String, dynamic>{});
  b.competition.id = "groupA";
  b.competition.name = "Group A";
  b.participants.addAll([
    EventParticipantDto((p) => p
      ..entityId = "g2"
      ..name = "G2"
      ..isWinner = true),
    EventParticipantDto((p) => p
      ..entityId = "th"
      ..name = "TH"
      ..isWinner = false),
  ]);
  b.context.stakes = null;
  return b.build();
}

CompetitionResponseDto _competition({required String id, required String name, List<CompetitionChildDto> children = const [], List<CompetitionStandingDto> standings = const []}) {
  return CompetitionResponseDto((b) => b
    ..id = id
    ..name = name
    ..kind = "tournament"
    ..sourceUpdatedAt = "2026-09-26T00:00:00Z"
    ..children.addAll(children)
    ..standings.addAll(standings));
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

// Poule GSL réaliste (Ouverture ×2 → Vainqueurs/Élimination → Decider),
// même structure que Group A/B sur le vrai Champions 2026 : sert à vérifier
// que l'arbre (pas le classement, retiré) s'affiche correctement.
BracketResponseDto _groupBracket() {
  final opening1 = _node(
    eventId: "g-open1",
    name: "Opening Match 1",
    status: "finished",
    round: 2,
    participants: [_participant(entityId: "g2", name: "G2", isWinner: true), _participant(entityId: "th", name: "TH", isWinner: false)],
  );
  final opening2 = _node(
    eventId: "g-open2",
    name: "Opening Match 2",
    status: "finished",
    round: 2,
    participants: [_participant(entityId: "t1", name: "T1", isWinner: true), _participant(entityId: "kru", name: "KRÜ", isWinner: false)],
  );
  final winners = _node(
    eventId: "g-winners",
    name: "Winners Match",
    status: "finished",
    round: 1,
    participants: [_participant(entityId: "g2", name: "G2", isWinner: true), _participant(entityId: "t1", name: "T1", isWinner: false)],
  );
  final elimination = _node(eventId: "g-elim", name: "Elimination Match", round: 1);
  final decider = _node(eventId: "g-decider", name: "Decider Match", round: 0);
  return BracketResponseDto((b) => b
    ..format = "groups_gsl"
    ..sourceUpdatedAt = "2026-09-26T00:00:00Z"
    ..nodes.addAll([opening1, opening2, winners, elimination, decider])
    ..links.addAll([
      _link(from: "g-open1", to: "g-winners", outcome: "winner"),
      _link(from: "g-open2", to: "g-winners", outcome: "winner"),
      _link(from: "g-open1", to: "g-elim", outcome: "loser"),
      _link(from: "g-open2", to: "g-elim", outcome: "loser"),
      _link(from: "g-winners", to: "g-decider", outcome: "loser"),
      _link(from: "g-elim", to: "g-decider", outcome: "winner"),
    ]));
}

Future<void> _pump(WidgetTester tester, {List<String>? calls}) {
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
        competitionDetailProvider("groupA").overrideWith((ref) async => _competition(id: "groupA", name: "Group A")),
        bracketProvider("groupA").overrideWith((ref) async => _groupBracket()),
        bracketProvider("playoffs").overrideWith((ref) async => bracket),
        // Le tap sur une case de l'arbre de poule pousse `NextMatchScreen` :
        // sans ce mock, l'appel réseau réel ne se résout jamais.
        eventProvider("g-open1").overrideWith((ref) async => _detailEvent()),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = false
          ..morningDigest = false)),
        overrideFollowsRecording([
          FollowStateDto((b) => b
            ..id = "sub-g2"
            ..targetType = "entity"
            ..targetId = "g2"
            ..level = "all"
            ..notifyReminder = true
            ..notifyStart = true
            ..notifyResult = true
            ..muted = false
            ..name = "G2"),
        ], calls ?? []),
      ],
      child: const MaterialApp(
        theme: null,
        home: BracketScreen(competitionId: "champions", title: "Champions", subtitle: "Phase de groupes"),
      ),
    ),
  );
}

void main() {
  testWidgets("onglet Groupes : arbre de qualification (Ouverture, Vainqueurs, Élimination, Decider, Qualifiés)", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // G2 apparaît dans l'Ouverture, le match Vainqueurs ET la case Qualifiés
    // (gagné son match Vainqueurs, pas besoin de Decider).
    expect(find.text("G2"), findsWidgets);
    // Le 2e nom de la case Qualifiés (via le Decider, pas encore joué) reste un placeholder.
    expect(find.text("?"), findsOneWidget);
    // Match pas encore joué : même logique de placeholder que le repêchage.
    expect(find.textContaining("Perdant de"), findsWidgets);
  });

  testWidgets("onglet Groupes : toucher une case ouvre le détail du match", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // "TH" n'apparaît que dans la case Ouverture 1 (g-open1) : cible sans ambiguïté.
    await tester.tap(find.text("TH"));
    await tester.pumpAndSettle();

    expect(find.byType(NextMatchScreen), findsOneWidget);
    expect(find.text("Group A"), findsOneWidget); // nom de la compétition dans l'en-tête
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

  testWidgets("la page compétition a un bouton Suivre qui abonne la compétition (J10)", (tester) async {
    final calls = <String>[];
    await _pump(tester, calls: calls);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Suivre"));
    await tester.pump();

    expect(calls, ["follow competition champions"]);
    expect(find.text("Suivi"), findsOneWidget);

    await tester.tap(find.text("Suivi"));
    await tester.pump();
    expect(calls, ["follow competition champions", "unfollow competition champions"]);
  });
}
