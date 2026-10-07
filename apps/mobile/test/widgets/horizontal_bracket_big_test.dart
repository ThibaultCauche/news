import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/bracket/bracket_view.dart";
import "package:mobile/widgets/bracket_match_card.dart";
import "package:mobile/widgets/horizontal_bracket.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

class _Pyramid extends BracketViewNotifier {
  @override
  BracketView build() => BracketView.pyramid;
}

// Un petit tableau (Top 8) : 2 matchs.
BracketResponseDto _tiny() => BracketResponseDto((b) => b
  ..format = "double_elim"
  ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
  ..nodes.addAll([
    for (final id in ["a", "b"])
      BracketNodeDto((n) => n
        ..eventId = id
        ..name = id == "a" ? "Grand final" : "Upper bracket semifinal 1"
        ..status = "finished"
        ..round = id == "a" ? 0 : 1
        ..participants.addAll([
          for (final k in [0, 1])
            BracketParticipantDto((p) => p
              ..entityId = "$id$k"
              ..name = "P$id$k"
              ..isWinner = k == 0),
        ])),
  ]));

// Un grand tableau (Top 64 de Smash, J27) dessiné dès le premier affichage : des cases visibles, pas un écran vide.
BracketResponseDto _single64() {
  final nodes = <BracketNodeDto>[];
  final links = <BracketLinkDto>[];
  var round = 1;
  var count = 32;
  var previous = <String>[];
  while (count >= 1) {
    final ids = [for (var i = 0; i < count; i++) "r$round-$i"];
    for (final id in ids) {
      nodes.add(BracketNodeDto((b) => b
        ..eventId = id
        ..name = count == 1 ? "Grand final" : "Upper bracket round $round match 1"
        ..status = "finished"
        // Tour radial de l'API : 0 = la finale, croissant vers l'extérieur.
        ..round = 6 - round
        ..participants.addAll([
          for (final k in [0, 1])
            BracketParticipantDto((p) => p
              ..entityId = "$id-$k"
              ..name = "Joueur $id $k"
              ..shortName = "J$k"
              ..isWinner = k == 0),
        ])));
    }
    for (var i = 0; i < previous.length; i++) {
      links.add(BracketLinkDto((b) => b
        ..fromEventId = previous[i]
        ..toEventId = ids[i ~/ 2]
        ..outcome = "winner"
        ..slot = i % 2));
    }
    previous = ids;
    round++;
    count ~/= 2;
  }
  return BracketResponseDto((b) => b
    ..format = "single_elim"
    ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
    ..nodes.addAll(nodes)
    ..links.addAll(links));
}

void main() {
  testWidgets("grande pyramide : des cases se dessinent dans la fenêtre dès le premier affichage", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Column(children: [Expanded(child: ClipRect(child: HorizontalBracket(bracket: _single64(), pannable: true)))])),
      ),
    ));
    await tester.pump();

    final cards = find.byType(BracketMatchCard);
    expect(cards, findsWidgets);
    final onScreen = [
      for (final e in cards.evaluate())
        if (tester.getRect(find.byWidget(e.widget)).overlaps(const Rect.fromLTWH(0, 0, 360, 700))) e,
    ];
    expect(onScreen, isNotEmpty, reason: "toutes les cases sont hors de la fenêtre : écran vide");
  });

  testWidgets("tournoi 1 contre 1 : le Top 64 s'affiche tour par tour, pas en pyramide de 4 500 points de haut", (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    CompetitionChildDto child(String id, String name) => CompetitionChildDto((b) => b
      ..id = id
      ..name = name
      ..kind = "tournament"
      ..hasEvents = true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        overrideSignedInForTest(),
        bracketViewProvider.overrideWith(_Pyramid.new),
        competitionDetailProvider("serie").overrideWith((ref) async => CompetitionResponseDto((b) => b
          ..id = "serie"
          ..name = "Genesis"
          ..kind = "serie"
          ..game = "super-smash-bros-ultimate"
          ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
          ..children.addAll([child("t8", "Top 8"), child("t64", "Top 64")]))),
        bracketProvider("t8").overrideWith((ref) async => _tiny()),
        bracketProvider("t64").overrideWith((ref) async => _single64()),
        overrideFollowsWith(const []),
      ],
      child: const MaterialApp(home: BracketScreen(competitionId: "serie", title: "Genesis", subtitle: "")),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Top 64"));
    await tester.pumpAndSettle();

    final onScreen = [
      for (final e in find.byType(BracketMatchCard).evaluate())
        if (tester.getRect(find.byWidget(e.widget)).overlaps(const Rect.fromLTWH(0, 0, 360, 780))) e,
    ];
    expect(onScreen.length, greaterThan(3), reason: "le Top 64 reste vide");
    // Un grand tableau se lit tour par tour : un titre par tour, du premier tour vers la finale.
    expect(find.text("TABLEAU PRINCIPAL, TOUR 1"), findsOneWidget);
  });
}
