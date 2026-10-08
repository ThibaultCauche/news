import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/features/politics/quiz_screen.dart";
import "package:news_api_client/news_api_client.dart";

QuizQuestionDto _question(int i, String group) => QuizQuestionDto((b) => b
  ..id = "evt-$i:G$i"
  ..eventId = "evt-$i"
  ..lawName = "Texte numéro $i"
  ..lawId = "law-$i"
  ..date = "2026-07-0$i"
  ..groupName = group
  ..choices.addAll(["pour", "contre", "abstention"]));

QuizDto _quiz({bool signedIn = false}) => QuizDto((b) => b
  ..day = "2026-10-09"
  ..signedIn = signedIn
  ..answered = 0
  ..correct = 0
  ..streak = signedIn ? 3 : 0
  ..bestStreak = signedIn ? 9 : 0
  ..questions.addAll([_question(1, "Alpha"), _question(2, "Beta")]));

// La correction est calculée ici comme le ferait le serveur : « Alpha » a voté pour, « Beta » contre.
Future<QuizAnswerResultDto> _grade(QuizQuestionDto q, String choice) async {
  final answer = q.groupName == "Alpha" ? "pour" : "contre";
  return QuizAnswerResultDto((b) => b
    ..questionId = q.id
    ..choice = choice
    ..correct = choice == answer
    ..answer = answer
    ..group.replace(VoteGroupDto((g) => g
      ..id = "G"
      ..name = q.groupName
      ..members = 10
      ..pour = answer == "pour" ? 9 : 0
      ..contre = answer == "contre" ? 8 : 0
      ..abst = 0
      ..nonVotants = 1
      ..position = answer == "pour" ? VoteGroupDtoPositionEnum.pour : VoteGroupDtoPositionEnum.contre))
    ..vote.replace(VoteOutcomeDto((v) => v
      ..sort = VoteOutcomeDtoSortEnum.adopt
      ..pour = 300
      ..contre = 200
      ..abst = 10
      ..sentence = "Adopté : 300 pour, 200 contre, 10 abstentions"))
    ..eventId = q.eventId
    ..lawId = q.lawId
    ..lawName = q.lawName
    ..date = q.date
    ..sourceUrl = "https://www.assemblee-nationale.fr/dyn/17/scrutins/1"
    ..recorded = false);
}

void main() {
  setUpAll(() => initializeDateFormatting("fr_FR"));

  testWidgets("le quiz pose une question, corrige avec les chiffres officiels et la source, puis donne le bilan", (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [quizProvider.overrideWith((ref) async => _quiz()), quizAnswerProvider.overrideWithValue(_grade)],
      child: const MaterialApp(home: QuizScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text("QUESTION 1 SUR 2"), findsOneWidget);
    expect(find.text("Alpha"), findsOneWidget);
    expect(find.text("Texte numéro 1"), findsOneWidget);
    // Les trois choix sont toujours les mêmes, dans le même ordre.
    expect(find.text("Pour"), findsOneWidget);
    expect(find.text("Contre"), findsOneWidget);
    expect(find.text("Abstention"), findsOneWidget);
    // Sans compte : pas de série.
    expect(find.textContaining("Série de"), findsNothing);

    await tester.tap(find.text("Pour"));
    await tester.pumpAndSettle();
    expect(find.text("Bonne réponse"), findsOneWidget);
    expect(find.text("Alpha a voté : Pour"), findsOneWidget);
    expect(find.textContaining("Adopté : 300 pour"), findsOneWidget);
    expect(find.text("Source officielle"), findsOneWidget);
    // Les choix disparaissent : une seule réponse par question.
    expect(find.text("Abstention"), findsNothing);

    await tester.tap(find.text("Question suivante"));
    await tester.pumpAndSettle();
    expect(find.text("QUESTION 2 SUR 2"), findsOneWidget);
    expect(find.text("Beta"), findsOneWidget);

    await tester.tap(find.text("Pour"));
    await tester.pumpAndSettle();
    expect(find.text("Pas cette fois"), findsOneWidget);
    expect(find.text("Beta a voté : Contre"), findsOneWidget);

    await tester.tap(find.text("Voir mon score"));
    await tester.pumpAndSettle();
    expect(find.text("1 / 2"), findsOneWidget);
    expect(find.text("bonne réponse aujourd'hui"), findsOneWidget);
    expect(find.text("Connecte-toi pour garder ta série de jours."), findsOneWidget);
  });

  testWidgets("avec un compte, la série et le record s'affichent", (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [quizProvider.overrideWith((ref) async => _quiz(signedIn: true)), quizAnswerProvider.overrideWithValue(_grade)],
      child: const MaterialApp(home: QuizScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Série de 3 jours"), findsOneWidget);
    expect(find.text("Record : 9"), findsOneWidget);
  });

  testWidgets("une question déjà répondue ne se repose pas : le quiz reprend à la suivante, ou au bilan", (tester) async {
    final done = QuizDto((b) => b
      ..day = "2026-10-09"
      ..signedIn = true
      ..answered = 2
      ..correct = 2
      ..streak = 1
      ..bestStreak = 1
      ..questions.addAll([
        _question(1, "Alpha").rebuild((q) => q
          ..myChoice = "pour"
          ..myCorrect = true),
        _question(2, "Beta").rebuild((q) => q
          ..myChoice = "contre"
          ..myCorrect = true),
      ]));
    await tester.pumpWidget(ProviderScope(
      overrides: [quizProvider.overrideWith((ref) async => done), quizAnswerProvider.overrideWithValue(_grade)],
      child: const MaterialApp(home: QuizScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text("2 / 2"), findsOneWidget);
    expect(find.text("Cinq nouvelles questions demain."), findsOneWidget);
    expect(find.text("Connecte-toi pour garder ta série de jours."), findsNothing);
  });
}
