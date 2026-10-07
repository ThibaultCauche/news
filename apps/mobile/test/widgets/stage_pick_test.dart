import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/auth/account.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/bracket/stage_pick.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

class _SignedOut extends SignedInNotifier {
  @override
  bool build() => false;
}

StagePickTeamDto _team(String code, {StagePickTeamDtoStateEnum state = StagePickTeamDtoStateEnum.playing}) => StagePickTeamDto((b) => b
  ..entityId = code.toLowerCase()
  ..name = "Team $code"
  ..shortName = code
  ..state = state);

StagePickDto _pick({bool open = true, bool locked = false, List<String> picks = const [], StagePickScoreDto? score}) => StagePickDto((b) => b
  ..competitionId = "swiss"
  ..open = open
  ..locked = locked
  ..max = 2
  ..picks.addAll(picks)
  ..score = score?.toBuilder()
  ..teams.addAll([
    _team("A", state: StagePickTeamDtoStateEnum.qualified),
    _team("B", state: StagePickTeamDtoStateEnum.eliminated),
    _team("C"),
    _team("D"),
  ]));

StagePickScoreDto _score(int correct, int wrong, int pending) => StagePickScoreDto((b) => b
  ..correct = correct
  ..wrong = wrong
  ..pending = pending);

UserSettingDto _settings(bool spoilerFree) => UserSettingDto((b) => b
  ..spoilerFree = spoilerFree
  ..morningDigest = false
  ..notifyForumReplies = false
  ..notifyForumThreads = false
  ..notifyMatchReminder = true
  ..notifyMatchStart = true
  ..notifyMatchResult = true
  ..notifyQualification = true
  ..notifyPredictionReminders = true);

Widget _app(StagePickDto? pick, {bool spoilerFree = false, bool signedIn = true}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        signedIn ? overrideSignedInForTest() : signedInProvider.overrideWith(_SignedOut.new),
        stagePickProvider("swiss").overrideWith((ref) async => pick),
        userSettingProvider.overrideWith((ref) async => _settings(spoilerFree)),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StagePickCard(competitionId: "swiss")))),
    );

void main() {
  testWidgets("avant le début : invitation à choisir, rien de choisi", (tester) async {
    await tester.pumpWidget(_app(_pick()));
    await tester.pumpAndSettle();
    expect(find.text("TON PRONOSTIC"), findsOneWidget);
    expect(find.textContaining("Quelles 2 équipes vont se qualifier ?"), findsOneWidget);
    expect(find.text("Choisir mes équipes"), findsOneWidget);
  });

  testWidgets("la feuille limite le choix à la moitié des équipes", (tester) async {
    await tester.pumpWidget(_app(_pick()));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Choisir mes équipes"));
    await tester.pumpAndSettle();

    expect(find.text("0/2"), findsOneWidget);
    await tester.tap(find.text("Team A"));
    await tester.tap(find.text("Team B"));
    await tester.pump();
    expect(find.text("2/2"), findsOneWidget);

    // Au maximum, une troisième équipe ne se coche plus.
    await tester.tap(find.text("Team C"));
    await tester.pump();
    expect(find.text("2/2"), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, "Team C")).onChanged, isNull);
  });

  testWidgets("étape lancée : le décompte des bonnes, ratées et en cours", (tester) async {
    await tester.pumpWidget(_app(_pick(locked: true, picks: ["a", "b", "c"], score: _score(1, 1, 1))));
    await tester.pumpAndSettle();
    expect(find.text("1 bonne · 1 ratée · 1 en cours"), findsOneWidget);
    expect(find.text("Choisir mes équipes"), findsNothing);
  });

  testWidgets("en sans spoil, les résultats du pronostic restent masqués", (tester) async {
    await tester.pumpWidget(_app(_pick(locked: true, picks: ["a", "b"], score: _score(1, 1, 0)), spoilerFree: true));
    await tester.pumpAndSettle();
    expect(find.textContaining("Résultats masqués"), findsOneWidget);
    expect(find.textContaining("bonne"), findsNothing);
  });

  testWidgets("rien à montrer sans équipes connues, ni pour un invité", (tester) async {
    await tester.pumpWidget(_app(_pick(open: false)));
    await tester.pumpAndSettle();
    expect(find.text("TON PRONOSTIC"), findsNothing);

    await tester.pumpWidget(_app(_pick(), signedIn: false));
    await tester.pumpAndSettle();
    expect(find.text("TON PRONOSTIC"), findsNothing);
  });
}
