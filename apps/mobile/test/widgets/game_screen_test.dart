import "package:built_collection/built_collection.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/valorant_season/season_data.dart";
import "package:mobile/features/competitions/game_screen.dart";
import "package:mobile/features/forum/forum_providers.dart";
import "package:mobile/features/learn/learn_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../competitions_test_helpers.dart";
import "../follows_test_helpers.dart";

// Noms longs et réels (pas les 6 étapes fictives de la maquette) : c'est ce
// volume-là qui a fait planter `OverflowBox` (contraintes non bornées, la
// carte vit dans une `ListView`) — un test avec des noms courts ne l'aurait
// pas repéré.
SeasonStep _step(String id, String name, {DateTime? startsAt, DateTime? endsAt}) =>
    SeasonStep(id: id, name: name, status: null, startsAt: startsAt, endsAt: endsAt);

final _valorant = CatalogGameDto((b) => b
  ..slug = "valorant"
  ..name = "Valorant"
  ..leagues = ListBuilder<CatalogLeagueDto>());

void main() {
  testWidgets("frise de saison : pas d'exception de mise en page avec de vrais noms longs", (tester) async {
    final now = DateTime.now();
    final steps = [
      _step("kickoff", "Kickoff 2026", startsAt: now.subtract(const Duration(days: 60)), endsAt: now.subtract(const Duration(days: 50))),
      _step("masters1", "Masters Londres 2026", startsAt: now.subtract(const Duration(days: 45)), endsAt: now.subtract(const Duration(days: 40))),
      _step("emea1", "EMEA Stage 1 2026", startsAt: now.subtract(const Duration(days: 35)), endsAt: now.subtract(const Duration(days: 25))),
      _step("americas1", "Americas Stage 1 2026", startsAt: now.subtract(const Duration(days: 35)), endsAt: now.subtract(const Duration(days: 25))),
      _step("champions", "Champions 2026", startsAt: now.subtract(const Duration(hours: 1)), endsAt: now.add(const Duration(days: 20))),
    ];
    final overview = SeasonOverview(
      rootCompetitionId: "vct",
      steps: steps,
      currentStep: steps.last,
      progress: 0.93,
      currentMatches: const [],
      playedSteps: steps.sublist(0, steps.length - 1),
      liquipediaContext: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          valorantSeasonProvider.overrideWith((ref) async => overview),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideFollowsWith(const []),
          overrideFavoriteGamesWith(const []),
          // `_NowCard` cherche des poules parmi les enfants de l'étape en
          // cours (`GroupBracketTree`) : sans ce mock, l'appel réseau réel
          // ne se résout jamais et laisse un timer pendant à la fin du test.
          competitionDetailProvider("champions").overrideWith((ref) async => CompetitionResponseDto((b) => b
            ..id = "champions"
            ..name = "Champions 2026"
            ..kind = "tournament"
            ..sourceUpdatedAt = "2026-09-27T00:00:00Z")),
        ],
        child: MaterialApp(home: GameScreen(game: _valorant)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text("CHAMPIONS 2026"), findsOneWidget);
    expect(find.text("À venir"), findsOneWidget);
  });

  testWidgets("carte Maintenant : une poule (Group A) affiche l'arbre plutôt que des tuiles de match", (tester) async {
    final now = DateTime.now();
    final step = _step("champions", "Champions 2026", startsAt: now.subtract(const Duration(hours: 1)), endsAt: now.add(const Duration(days: 20)));
    final overview = SeasonOverview(
      rootCompetitionId: "vct",
      steps: [step],
      currentStep: step,
      progress: 0.5,
      currentMatches: const [],
      playedSteps: const [],
      liquipediaContext: null,
    );
    final opening = BracketNodeDto((b) => b
      ..eventId = "open1"
      ..name = "Opening Match 1"
      ..status = "finished"
      ..round = 0
      ..participants.addAll([
        BracketParticipantDto((p) => p
          ..entityId = "g2"
          ..name = "G2"
          ..isWinner = true),
        BracketParticipantDto((p) => p
          ..entityId = "th"
          ..name = "TH"
          ..isWinner = false),
      ]));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          valorantSeasonProvider.overrideWith((ref) async => overview),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideFollowsWith(const []),
          overrideFavoriteGamesWith(const []),
          competitionDetailProvider("champions").overrideWith((ref) async => CompetitionResponseDto((b) => b
            ..id = "champions"
            ..name = "Champions 2026"
            ..kind = "tournament"
            ..sourceUpdatedAt = "2026-09-27T00:00:00Z"
            ..children.add(CompetitionChildDto((c) => c
              ..id = "groupA"
              ..name = "Group A"
              ..kind = "tournament"
              ..hasEvents = true)))),
          competitionDetailProvider("groupA").overrideWith((ref) async => CompetitionResponseDto((b) => b
            ..id = "groupA"
            ..name = "Group A"
            ..kind = "tournament"
            ..sourceUpdatedAt = "2026-09-27T00:00:00Z")),
          bracketProvider("groupA").overrideWith((ref) async => BracketResponseDto((b) => b
            ..format = "groups_gsl"
            ..sourceUpdatedAt = "2026-09-27T00:00:00Z"
            ..nodes.add(opening))),
        ],
        child: MaterialApp(home: GameScreen(game: _valorant)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text("GROUP A"), findsOneWidget);
    expect(find.text("G2"), findsWidgets);
    // Plus de tuile `EventCard` générique pour ces matchs : remplacée par l'arbre.
    expect(find.text("Aucun match programmé pour l'instant."), findsNothing);
  });

  testWidgets("onglets : celui qu'on choisit au bord de la capsule défile en entier dans le cadre (écran de 360)", (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          valorantSeasonProvider.overrideWith((ref) async => null),
          forumEnabledProvider.overrideWithValue(true),
          learnGamesProvider.overrideWith((ref) async => {"valorant"}),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideFollowsWith(const []),
          overrideFavoriteGamesWith(const []),
        ],
        child: MaterialApp(home: GameScreen(game: _valorant)),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Hors cadre à cette largeur : on déclenche le tap directement, comme sur le bord visible d'un vrai écran.
    tester.widget<GestureDetector>(find.ancestor(of: find.text("Discussions"), matching: find.byType(GestureDetector)).first).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final right = tester.getTopRight(find.text("Discussions")).dx;
    expect(right, lessThanOrEqualTo(360));
  });
}
