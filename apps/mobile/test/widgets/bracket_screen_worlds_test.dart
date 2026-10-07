import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:mobile/features/bracket/ranking_view.dart";
import "package:mobile/features/bracket/stage_pick.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

// Les Worlds de League of Legends : un play-in, une phase suisse (« Group Stage ») et une phase finale à simple
// élimination, donc sans repêchage (J23).

CompetitionChildDto _child(String id, String name) => CompetitionChildDto((b) => b
  ..id = id
  ..name = name
  ..kind = "tournament"
  ..hasEvents = true);

CompetitionResponseDto _competition(String id, String name, {List<CompetitionChildDto> children = const [], String game = "league-of-legends"}) =>
    CompetitionResponseDto((b) => b
      ..id = id
      ..name = name
      ..kind = "tournament"
      ..game = game
      ..sourceUpdatedAt = "2026-10-20T00:00:00Z"
      ..children.addAll(children));

BracketParticipantDto _p(String code, {required bool win}) => BracketParticipantDto((b) => b
  ..entityId = code.toLowerCase()
  ..name = "Team $code"
  ..shortName = code
  ..score = win ? 1 : 0
  ..isWinner = win);

BracketNodeDto _swissMatch(int round, String winner, String loser) => BracketNodeDto((b) => b
  ..eventId = "r$round-$winner$loser"
  ..name = "Round $round: $winner vs $loser"
  ..status = "finished"
  ..round = 0
  ..startsAt = "2026-10-2${round}T10:00:00Z"
  ..participants.addAll([_p(winner, win: true), _p(loser, win: false)]));

BracketResponseDto _swiss() => BracketResponseDto((b) => b
  ..format = "swiss"
  ..sourceUpdatedAt = "2026-10-20T00:00:00Z"
  ..nodes.addAll([_swissMatch(1, "A", "B"), _swissMatch(1, "C", "D"), _swissMatch(2, "A", "C"), _swissMatch(2, "B", "D")])
  // Une ronde 3 pas jouée : la phase suisse n'est pas terminée.
  ..nodes.add(BracketNodeDto((n) => n
    ..eventId = "r3"
    ..name = "Round 3: TBD vs TBD"
    ..status = "scheduled"
    ..round = 0)));

BracketResponseDto _playoffsNotStarted() => BracketResponseDto((b) => b
  ..format = "single_elim"
  ..sourceUpdatedAt = "2026-10-20T00:00:00Z"
  ..nodes.addAll([
    BracketNodeDto((n) => n
      ..eventId = "qf1"
      ..name = "Quarterfinal 1: TBD vs TBD"
      ..status = "scheduled"
      ..round = 1),
    BracketNodeDto((n) => n
      ..eventId = "final"
      ..name = "Grand final: TBD vs TBD"
      ..status = "scheduled"
      ..round = 0),
  ])
  ..links.add(BracketLinkDto((l) => l
    ..fromEventId = "qf1"
    ..toEventId = "final"
    ..outcome = "winner"
    ..slot = 0)));

BracketResponseDto _playIn() => BracketResponseDto((b) => b
  ..format = "double_elim"
  ..sourceUpdatedAt = "2026-10-20T00:00:00Z"
  ..nodes.add(BracketNodeDto((n) => n
    ..eventId = "pi1"
    ..name = "Upper Bracket Final: TBD vs TBD"
    ..status = "scheduled"
    ..round = 0)));

RankingResponseDto _ranking() => RankingResponseDto((b) => b
  ..finished = false
  ..sourceUpdatedAt = "2026-10-20T00:00:00Z"
  ..entries.add(RankingEntryDto((e) => e
    ..entityId = "a"
    ..name = "Team A"
    ..shortName = "A"
    ..rank = 1
    ..status = RankingEntryDtoStatusEnum.inRace
    ..stage = "Group Stage"
    ..stageFormat = "swiss"
    ..wins = 2
    ..losses = 0
    ..qualified = false)));

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          overrideSignedInForTest(),
          competitionDetailProvider("worlds").overrideWith((ref) async => _competition("worlds", "Worlds 2026", children: [_child("playin", "Play-In"), _child("swiss", "Group Stage"), _child("playoffs", "Playoffs")])),
          competitionDetailProvider("playin").overrideWith((ref) async => _competition("playin", "Play-In")),
          competitionDetailProvider("swiss").overrideWith((ref) async => _competition("swiss", "Group Stage")),
          bracketProvider("playin").overrideWith((ref) async => _playIn()),
          bracketProvider("swiss").overrideWith((ref) async => _swiss()),
          bracketProvider("playoffs").overrideWith((ref) async => _playoffsNotStarted()),
          stagePickProvider("swiss").overrideWith((ref) async => null),
          rankingProvider("worlds").overrideWith((ref) async => _ranking()),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false
            ..notifyForumReplies = false
            ..notifyForumThreads = false
            ..notifyMatchReminder = true
            ..notifyMatchStart = true
            ..notifyMatchResult = true
            ..notifyQualification = true
            ..notifyPredictionReminders = true)),
          overrideFollowsWith(const []),
        ],
        child: const MaterialApp(home: BracketScreen(competitionId: "worlds", title: "Worlds 2026", subtitle: "En cours")),
      ),
    );

void main() {
  testWidgets("Worlds : onglets Groupes, Phase finale et Classement, sans Repêchage (simple élimination)", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text("Groupes"), findsOneWidget);
    expect(find.text("Phase finale"), findsOneWidget);
    expect(find.text("Classement"), findsOneWidget);
    expect(find.text("Repêchage"), findsNothing);
    // Le fil d'Ariane suit le jeu de la compétition, plus « Valorant » en dur.
    expect(find.text("League of Legends"), findsOneWidget);
  });

  testWidgets("Worlds : l'onglet Groupes montre le play-in puis la phase suisse par rondes", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("PLAY-IN"), findsOneWidget);
    expect(find.text("GROUP STAGE"), findsOneWidget);
    expect(find.text("RONDE 1"), findsWidgets);
    expect(find.text("Bilan 1-0"), findsOneWidget);
    expect(find.text("QUALIFIÉES (0)"), findsOneWidget);
    // Le play-in, qui passe avant la phase suisse, est plus haut sur l'écran.
    expect(tester.getTopLeft(find.text("PLAY-IN")).dy, lessThan(tester.getTopLeft(find.text("GROUP STAGE")).dy));
  });

  testWidgets("Worlds : l'onglet Classement liste les équipes de la série", (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Classement"));
    await tester.pumpAndSettle();

    expect(find.text("Classement en cours"), findsOneWidget);
    expect(find.text("Team A"), findsOneWidget);
    expect(find.text("En course · phase suisse"), findsOneWidget);
  });
}
