import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_painter.dart";
import "package:mobile/features/bracket/bracket_view.dart";
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

class _CircleView extends BracketViewNotifier {
  @override
  BracketView build() => BracketView.circle;
}

Future<void> _pump(WidgetTester tester, {List<String>? calls, bool circle = false}) {
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
        overrideSignedInForTest(),
        if (circle) bracketViewProvider.overrideWith(_CircleView.new),
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
  testWidgets("la phase finale a commencé : l'écran s'ouvre sur « Phase finale », sans toucher aux onglets", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text("QUART DE FINALE 1"), findsOneWidget);
    expect(find.text("OUVERTURE 1"), findsNothing);
  });

  testWidgets("onglet Groupes : pyramide (Ouverture, Vainqueurs, Élimination, Decider, Qualifiés)", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Groupes"));
    await tester.pumpAndSettle();

    expect(find.text("OUVERTURE 1"), findsOneWidget);
    expect(find.text("MATCH DES VAINQUEURS"), findsOneWidget);
    expect(find.text("MATCH D'ÉLIMINATION"), findsOneWidget);
    expect(find.text("MATCH DÉCISIF"), findsOneWidget);
    expect(find.text("QUALIFIÉS"), findsOneWidget);
    // G2 a gagné son match des vainqueurs : qualifié sans passer par le décisif.
    expect(find.text("G2"), findsWidgets);
    // Le décisif attend le gagnant de l'élimination ; le 2ᵉ qualifié n'est pas connu.
    expect(find.textContaining("Gagnant du match d'élimination"), findsOneWidget);
    expect(find.text("À déterminer"), findsOneWidget);

    // Trois colonnes : 3 cases (Ouverture 1 et 2, Élimination), 2 (Vainqueurs, Décisif), 1 (Qualifiés).
    double x(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(x("OUVERTURE 2"), x("OUVERTURE 1"));
    expect(x("MATCH D'ÉLIMINATION"), x("OUVERTURE 1"));
    expect(x("MATCH DÉCISIF"), x("MATCH DES VAINQUEURS"));
    expect(x("MATCH DES VAINQUEURS"), greaterThan(x("OUVERTURE 1")));
    expect(x("QUALIFIÉS"), greaterThan(x("MATCH DÉCISIF")));
  });

  testWidgets("onglet Groupes : en cercle, les qualifiés au centre et l'élimination en troisième branche", (tester) async {
    await _pump(tester, circle: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Groupes"));
    await tester.pumpAndSettle();

    expect(find.text("QUALIFIÉS"), findsOneWidget);
    final painter = tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter)).painter as BracketPainter;
    // Deux moitiés qui se répondent : en haut les ouvertures (4) puis les vainqueurs (2) ; en bas l'élimination (2)
    // et les deux équipes du match des vainqueurs (2), puis le décisif (2 : gagnant de l'élimination, perdant des vainqueurs).
    expect(painter.tree.slots.where((s) => s.ring == 2), hasLength(8));
    expect(painter.tree.slots.where((s) => s.ring == 1), hasLength(4));
    expect(painter.tree.slots.map((s) => s.matchId), contains("g-elim"));
  });

  testWidgets("onglet Groupes : toucher une case ouvre le détail du match", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Groupes"));
    await tester.pumpAndSettle();

    // La première case « TH » est celle de l'Ouverture 1 (g-open1), la première du tableau.
    await tester.tap(find.text("TH").first);
    await tester.pumpAndSettle();

    expect(find.byType(NextMatchScreen), findsOneWidget);
    expect(find.text("Group A"), findsOneWidget); // nom de la compétition dans l'en-tête
  });

  testWidgets("onglet Phase finale : un cercle par équipe, l'équipe suivie (G2) en or", (tester) async {
    await _pump(tester, circle: true);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Phase finale"));
    await tester.pumpAndSettle();

    final customPaint = tester.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter),
    );
    final painter = customPaint.painter as BracketPainter;
    expect(painter.followedEntityIds, {"g2"});
    expect(painter.tree.center?.eventId, "final");
    expect(painter.tree.slots.map((s) => s.team?.shortName), ["G2", "TH"]);
    // Le tableau bas (repêchage) ne fait pas partie de l'arbre radial.
    expect(painter.tree.slots.map((s) => s.matchId), isNot(contains("lower1")));
    // La phrase de l'équipe suivie : G2 attend la finale, sans date.
    expect(find.textContaining("Prochain match de G2 : Grande finale"), findsOneWidget);
  });

  testWidgets("onglet Phase finale : pyramide par défaut, du premier tour à la grande finale", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Phase finale"));
    await tester.pumpAndSettle();

    expect(find.text("QUART DE FINALE 1"), findsOneWidget);
    expect(find.text("GRANDE FINALE"), findsOneWidget);
    // Le repêchage fait partie de la pyramide : sa case dit d'où viennent les équipes.
    expect(find.text("REPÊCHAGE · TOUR 1"), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter), findsNothing);
  });

  testWidgets("les deux ronds de la ligne du titre basculent entre pyramide et cercle", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Phase finale"));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel("Cercle"));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter), findsOneWidget);

    await tester.tap(find.bySemanticsLabel("Pyramide"));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter), findsNothing);
  });

  testWidgets("onglet Phase finale : toucher un cercle ouvre son match", (tester) async {
    await _pump(tester, circle: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Phase finale"));
    await tester.pumpAndSettle();

    final painter = tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter));
    final box = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BracketPainter));
    final layout = RadialLayout((painter.painter as BracketPainter).tree, box.size);
    final slot = (painter.painter as BracketPainter).tree.slots.first;
    expect(layout.matchAt(layout.position(slot)), "qf1");
    expect(layout.matchAt(layout.center), "final");
  });

  testWidgets("onglet Repêchage : l'équipe issue d'un match joué remplace le « Perdant du … »", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Repêchage"));
    await tester.pumpAndSettle();

    expect(find.text("COMMENT ÇA MARCHE"), findsOneWidget);
    expect(find.text("TH"), findsNWidgets(2)); // pastille + nom
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
