import "package:built_value/json_object.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/features/bracket/bracket_provider.dart";
import "package:mobile/features/competitions/competitions_data.dart" show catalogProvider;
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:mobile/features/politics/law_screen.dart";
import "package:mobile/features/politics/politics_screen.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

LawStepDto _step(String key, String label, LawStepDtoStateEnum state, {String? date, String? detail, LawVoteDto? vote}) => LawStepDto((b) => b
  ..key = key
  ..label = label
  ..state = state
  ..date = date
  ..detail = detail
  ..vote = vote?.toBuilder());

LawVoteDto _lawVote() => LawVoteDto((b) => b
  ..sort = LawVoteDtoSortEnum.adopt
  ..pour = 312
  ..contre = 198
  ..abst = 41
  ..sentence = "Adopté : 312 pour, 198 contre, 41 abstentions"
  ..eventId = "vote-1"
  ..numero = 1308);

LawDto _law() => LawDto((b) => b
  ..status = LawDtoStatusEnum.inProgress
  ..officialTitle = "Proposition de loi visant à plafonner la revente de billets"
  ..lawType = "Proposition de loi"
  ..sourceUrl = "https://www.assemblee-nationale.fr/dyn/17/dossiers/x"
  ..author.replace(LawAuthorDto((a) => a
    ..kind = LawAuthorDtoKindEnum.deputy
    ..name = "Ayda Hadizadeh"
    ..group = "Socialistes et apparentés"
    ..cosigners = 3))
  ..steps.addAll([
    _step("deposit", "Déposé à l'Assemblée", LawStepDtoStateEnum.done, date: "2025-05-12"),
    _step("committee1", "Examiné en commission à l'Assemblée", LawStepDtoStateEnum.done, date: "2025-06-03"),
    _step("vote1", "Voté par les députés", LawStepDtoStateEnum.done, date: "2025-06-18", vote: _lawVote()),
    _step("committee2", "Examiné en commission au Sénat", LawStepDtoStateEnum.current),
    _step("vote2", "Voté par les sénateurs", LawStepDtoStateEnum.todo),
    _step("agreement", "Accord final entre les deux chambres", LawStepDtoStateEnum.todo),
    _step("promulgation", "Promulgation", LawStepDtoStateEnum.todo),
  ]));

CompetitionResponseDto _competition(LawDto? law) => CompetitionResponseDto((b) => b
  ..id = "law-1"
  ..name = "Revente de billets"
  ..kind = "law"
  ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
  ..law = law?.toBuilder());

void main() {
  setUpAll(() => initializeDateFormatting("fr_FR"));

  testWidgets("l'écran d'une loi montre les étapes façon colis, l'étape en cours et le vote des députés", (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("law-1").overrideWith((ref) async => _competition(_law())), overrideFollowsWith(const []), catalogProvider.overrideWith((ref) async => CatalogDto((b) => b))],
      child: const MaterialApp(home: LawScreen(competitionId: "law-1")),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Proposition de loi visant à plafonner la revente de billets"), findsOneWidget);
    expect(find.text("En cours d'examen"), findsOneWidget);
    for (final label in ["Déposé à l'Assemblée", "Voté par les députés", "Examiné en commission au Sénat", "Promulgation"]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text("En ce moment"), findsOneWidget);
    expect(find.text("12 mai 2025"), findsOneWidget);
    // Le résultat du vote apparaît dans l'étape et dans « Les votes des députés ».
    expect(find.textContaining("Adopté : 312 pour, 198 contre"), findsNWidgets(2));
    expect(find.text("Ayda Hadizadeh, Socialistes et apparentés"), findsOneWidget);
    expect(find.text("et 3 cosignataires"), findsOneWidget);
    expect(find.textContaining("Légifrance"), findsNothing);
    expect(find.textContaining("Licence ouverte 2.0"), findsOneWidget);
  });

  testWidgets("un texte sans suivi le dit au lieu d'une page vide", (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [competitionDetailProvider("law-1").overrideWith((ref) async => _competition(null)), overrideFollowsWith(const []), catalogProvider.overrideWith((ref) async => CatalogDto((b) => b))],
      child: const MaterialApp(home: LawScreen(competitionId: "law-1")),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Ce texte n'a pas de suivi."), findsOneWidget);
  });

  testWidgets("l'écran d'un vote donne la phrase, la majorité et chaque groupe avec sa position", (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    VoteGroupDto group(String name, VoteGroupDtoPositionEnum position, {int pour = 0, int contre = 0}) => VoteGroupDto((b) => b
      ..id = name
      ..name = name
      ..members = 10
      ..pour = pour
      ..contre = contre
      ..abst = 0
      ..nonVotants = 10 - pour - contre
      ..position = position);
    final event = EventDetailResponseDto((b) => b
      ..id = "vote-1"
      ..kind = "vote"
      ..name = "L'ensemble de la proposition de loi"
      ..status = "finished"
      ..importance = 0
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
      ..result = JsonObject(<String, dynamic>{})
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "law-1"
        ..name = "Revente de billets"))
      ..context.replace(EventContextDto((c) => c))
      ..vote.replace(ScrutinDto((v) => v
        ..sort = ScrutinDtoSortEnum.adopt
        ..pour = 8
        ..contre = 7
        ..abst = 0
        ..sentence = "Adopté : 8 pour, 7 contre"
        ..numero = 1308
        ..date = "2025-06-18"
        ..announcement = "l'Assemblée nationale a adopté"
        ..voteType = "scrutin public solennel"
        ..nonVotants = 5
        ..votants = 15
        ..majority = 8
        ..sourceUrl = "https://www.assemblee-nationale.fr/dyn/17/scrutins/1308"
        ..lawId = "law-1"
        ..lawName = "Revente de billets"
        ..groups.addAll([group("Alpha", VoteGroupDtoPositionEnum.pour, pour: 8), group("Beta", VoteGroupDtoPositionEnum.contre, contre: 7)]))));
    await tester.pumpWidget(ProviderScope(
      overrides: [eventProvider("vote-1").overrideWith((ref) async => event), overrideFollowsWith(const [])],
      child: const MaterialApp(home: NextMatchScreen(eventId: "vote-1")),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Adopté : 8 pour, 7 contre"), findsOneWidget);
    expect(find.textContaining("majorité requise : 8 voix"), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("Hémicycle")), findsOneWidget);
    expect(find.text("Alpha"), findsOneWidget);
    expect(find.text("Pour"), findsWidgets);
    expect(find.text("Contre"), findsWidgets);
    // Ni score flouté ni « sans spoil » : un vote n'a rien à cacher.
    expect(find.textContaining("Maintiens pour révéler"), findsNothing);
    expect(find.text("Où en est ce texte ?"), findsOneWidget);
  });

  testWidgets("la page Politique liste votes, textes en cours et lois promulguées", (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overview = PoliticsOverviewDto((b) => b
      ..sourceUpdatedAt = "2026-10-08T00:00:00Z"
      ..votes.add(VoteCardDto((v) => v
        ..eventId = "vote-1"
        ..name = "L'ensemble de la proposition de loi"
        ..date = "2026-07-21"
        ..lawId = "law-1"
        ..lawName = "Protéger les mineurs sur les réseaux sociaux"
        ..outcome.replace(VoteOutcomeDto((o) => o
          ..sort = VoteOutcomeDtoSortEnum.adopt
          ..pour = 279
          ..contre = 81
          ..abst = 66
          ..sentence = "Adopté : 279 pour, 81 contre, 66 abstentions"))))
      ..inProgress.add(LawCardDto((l) => l
        ..id = "law-2"
        ..name = "Moderniser le titre-restaurant"
        ..lawType = "Proposition de loi"
        ..status = LawCardDtoStatusEnum.inProgress
        ..stepLabel = "Voté par les députés"
        ..lastDate = "2026-10-07"))
      ..promulgated.add(LawCardDto((l) => l
        ..id = "law-3"
        ..name = "Droit de chaque enfant à un avocat"
        ..lawType = "Proposition de loi"
        ..status = LawCardDtoStatusEnum.promulgated
        ..stepLabel = "Promulguée · loi n° 2026-630"
        ..lastDate = "2026-07-13")));
    await tester.pumpWidget(ProviderScope(
      overrides: [politicsOverviewProvider.overrideWith((ref) async => overview)],
      child: const MaterialApp(home: PoliticsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text("DERNIERS VOTES"), findsOneWidget);
    expect(find.text("TEXTES EN COURS"), findsOneWidget);
    expect(find.text("DERNIÈRES LOIS PROMULGUÉES"), findsOneWidget);
    expect(find.text("Adopté : 279 pour, 81 contre, 66 abstentions"), findsOneWidget);
    expect(find.text("Moderniser le titre-restaurant"), findsOneWidget);
    expect(find.textContaining("Promulguée · loi n° 2026-630"), findsOneWidget);

    await tester.tap(find.byTooltip("Notre règle de neutralité"));
    await tester.pumpAndSettle();
    expect(find.text("Ni pronostic ni commentaire"), findsOneWidget);
  });
}
