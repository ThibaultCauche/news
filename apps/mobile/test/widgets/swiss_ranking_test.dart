import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/ranking_view.dart";
import "package:mobile/features/bracket/stage_pick.dart";
import "package:mobile/features/bracket/swiss_view.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

UserSettingDto _settings({required bool spoilerFree}) => UserSettingDto((b) => b
  ..spoilerFree = spoilerFree
  ..morningDigest = false
  ..notifyForumReplies = false
  ..notifyForumThreads = false
  ..notifyMatchReminder = true
  ..notifyMatchStart = true
  ..notifyMatchResult = true
  ..notifyQualification = true
  ..notifyPredictionReminders = true);

BracketParticipantDto _p(String code, {required bool win}) => BracketParticipantDto((b) => b
  ..entityId = code.toLowerCase()
  ..name = "Team $code"
  ..shortName = code
  ..score = win ? 1 : 0
  ..isWinner = win);

BracketNodeDto _m(int round, String winner, String loser, {String status = "finished"}) => BracketNodeDto((b) => b
  ..eventId = "r$round-$winner$loser"
  ..name = "Round $round: $winner vs $loser"
  ..status = status
  ..round = 0
  ..startsAt = "2026-10-1${round}T10:00:00Z"
  ..participants.addAll([_p(winner, win: true), _p(loser, win: false)]));

RankingEntryDto _entry(int rank, String code, RankingEntryDtoStatusEnum status,
        {String stage = "Group Stage", String? format = "swiss", int wins = 0, int losses = 0, bool qualified = false}) =>
    RankingEntryDto((b) => b
      ..entityId = code.toLowerCase()
      ..name = "Team $code"
      ..shortName = code
      ..rank = rank
      ..status = status
      ..stage = stage
      ..stageFormat = format
      ..wins = wins
      ..losses = losses
      ..qualified = qualified);

RankingResponseDto _ranking() => RankingResponseDto((b) => b
  ..finished = false
  ..sourceUpdatedAt = "2026-10-12T00:00:00Z"
  ..entries.addAll([
    _entry(1, "A", RankingEntryDtoStatusEnum.champion, stage: "Playoffs", format: "single_elim", wins: 3),
    _entry(2, "B", RankingEntryDtoStatusEnum.inRace, wins: 2, losses: 1),
    _entry(2, "Q", RankingEntryDtoStatusEnum.inRace, wins: 3, losses: 1, qualified: true),
    _entry(3, "H", RankingEntryDtoStatusEnum.eliminated, losses: 3),
  ]));

Widget _app(Widget child, {required bool spoilerFree}) => ProviderScope(
      overrides: [
        userSettingProvider.overrideWith((ref) async => _settings(spoilerFree: spoilerFree)),
        overrideFollowsWith(const []),
        overrideSignedInForTest(),
        stagePickProvider("swiss").overrideWith((ref) async => null),
        rankingProvider("serie").overrideWith((ref) async => _ranking()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets("phase suisse : une colonne par ronde, les matchs par bilan, qualifiées et éliminées", (tester) async {
    final bracket = BracketResponseDto((b) => b
      ..format = "swiss"
      ..sourceUpdatedAt = "2026-10-12T00:00:00Z"
      ..nodes.addAll([_m(1, "A", "B"), _m(1, "C", "D"), _m(2, "A", "C"), _m(2, "B", "D"), _m(3, "A", "E"), _m(3, "D", "F")]));
    await tester.pumpWidget(_app(SwissView(bracket: bracket, competitionId: "swiss"), spoilerFree: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Le titre de la colonne, et celui de chaque case de la ronde (« Ronde 1 » en capitales).
    expect(find.text("RONDE 1"), findsWidgets);
    expect(find.text("RONDE 3"), findsWidgets);
    expect(find.text("Bilan 0-0"), findsOneWidget);
    expect(find.text("Bilan 1-0"), findsOneWidget);
    expect(find.text("Bilan 0-1"), findsOneWidget);
    expect(find.text("Bilan 2-0"), findsOneWidget);
    expect(find.text("QUALIFIÉES (1)"), findsOneWidget);
    expect(find.text("ÉLIMINÉES (0)"), findsOneWidget);
  });

  testWidgets("classement global : championne, en course, éliminée avec leur étape", (tester) async {
    await tester.pumpWidget(_app(const RankingView(competitionId: "serie"), spoilerFree: false));
    await tester.pumpAndSettle();

    expect(find.text("Classement en cours"), findsOneWidget);
    expect(find.text("Team A"), findsOneWidget);
    expect(find.text("Championne"), findsOneWidget);
    expect(find.text("En course · phase suisse"), findsOneWidget);
    expect(find.text("Qualifiée · phase suisse"), findsOneWidget);
    expect(find.text("Éliminée · phase suisse"), findsOneWidget);
    expect(find.text("2-1"), findsOneWidget);
  });

  testWidgets("sans spoil : le classement reste masqué jusqu'à « Afficher »", (tester) async {
    await tester.pumpWidget(_app(const RankingView(competitionId: "serie"), spoilerFree: true));
    await tester.pumpAndSettle();

    expect(find.text("Classement masqué (sans spoil)."), findsOneWidget);
    expect(find.text("Team A"), findsNothing);

    await tester.tap(find.text("Afficher"));
    await tester.pumpAndSettle();
    expect(find.text("Team A"), findsOneWidget);
  });

  testWidgets("classement : une phrase explique comment le lire, avec la règle de la phase suisse", (tester) async {
    await tester.pumpWidget(_app(const RankingView(competitionId: "serie"), spoilerFree: false));
    await tester.pumpAndSettle();
    expect(find.textContaining("En phase suisse, 3 victoires qualifient et 3 défaites éliminent."), findsOneWidget);
  });

  test("stageLabel nomme les étapes en français", () {
    expect(stageLabel("Group Stage", "swiss"), "phase suisse");
    expect(stageLabel("Playoffs", "single_elim"), "phase finale");
    expect(stageLabel("Play-In", "double_elim"), "play-in");
    expect(stageLabel("Group A", "groups_gsl"), "phase de groupes");
  });
}
