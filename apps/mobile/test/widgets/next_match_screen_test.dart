import "package:built_value/json_object.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/settings_provider.dart";
import "package:mobile/features/next_match/next_match_screen.dart";
import "package:mobile/widgets/glossary_sheet.dart";
import "package:news_api_client/news_api_client.dart";
import "../follows_test_helpers.dart";

/// Simule le tap sur un mot souligné d'un `Text.rich` : plus fiable qu'un tap
/// par coordonnées (`tester.tap`), qui hit-teste tout le `RichText` d'un coup.
/// Cherche dans tous les `RichText` de l'arbre (un `Text` normal en construit
/// un aussi, sans lien avec le nôtre) le premier `TextSpan` avec ce texte et un
/// `TapGestureRecognizer`.
void _tapSpan(WidgetTester tester, String text) {
  TapGestureRecognizer? recognizer;
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == text && span.recognizer is TapGestureRecognizer) {
        recognizer = span.recognizer as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (recognizer != null) break;
  }
  recognizer!.onTap!();
}

EventDetailResponseDto _event({required String status, int? scoreA, int? scoreB, String? stakes, String shortNameA = "G2", List<StreamDto> streams = const [], String? moreUrl}) {
  return EventDetailResponseDto((b) => b
    ..id = "evt-1"
    ..kind = "match"
    ..name = "G2 Esports vs Paper Rex"
    ..status = status
    ..bestOf = 3
    ..streams.addAll(streams)
    ..moreStreamersUrl = moreUrl
    ..importance = 3
    ..sourceUpdatedAt = "2026-09-27T00:00:00.000Z"
    ..result = JsonObject(<String, dynamic>{})
    ..competition.replace(CompetitionRefDto((c) => c
      ..id = "comp-1"
      ..name = "Champions 2026"))
    ..participants.addAll([
      EventParticipantDto((p) => p
        ..entityId = "team-a"
        ..name = "G2 Esports"
        ..shortName = shortNameA
        ..score = scoreA
        ..isWinner = scoreA != null && scoreB != null ? scoreA > scoreB : null),
      EventParticipantDto((p) => p
        ..entityId = "team-b"
        ..name = "Paper Rex"
        ..shortName = "PRX"
        ..score = scoreB
        ..isWinner = scoreA != null && scoreB != null ? scoreB > scoreA : null),
    ])
    ..context.replace(EventContextDto((c) => c
      ..stakes = stakes
      ..recentForm.add(RecentFormEntryDto((r) => r
        ..entityId = "team-a"
        ..results.addAll(["V", "D", "V", "V", "D"]))))));
}

Future<void> _pump(WidgetTester tester, EventDetailResponseDto event, {bool spoilerFree = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventProvider("evt-1").overrideWith((ref) async => event),
        userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
          ..spoilerFree = spoilerFree
          ..morningDigest = false)),
        overrideFollowsWith(const []),
      ],
      child: const MaterialApp(home: NextMatchScreen(eventId: "evt-1")),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  StreamDto stream(String channel, String lang, {String? name, bool? live}) => StreamDto((b) => b
    ..channel = channel
    ..url = "https://www.twitch.tv/$channel"
    ..language = lang
    ..displayName = name
    ..live = live);

  testWidgets("Regarder : un cercle par chaîne (ta langue d'abord) et « Autres streamers », avant et pendant le match (J21)", (tester) async {
    await _pump(tester, _event(status: "live", streams: [stream("valorant", "en", name: "VALORANT", live: true), stream("valorant_fr", "fr", name: "Valorant FR")], moreUrl: "https://www.twitch.tv/directory/category/valorant"));
    expect(find.text("REGARDER"), findsOneWidget);
    expect(find.text("Autres streamers"), findsOneWidget);
    // La langue du test n'est pas le français : on ne vérifie que la présence des deux cercles.
    expect(find.text("VALORANT"), findsOneWidget);
    expect(find.text("Valorant FR"), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0, streams: [stream("valorant", "en")], moreUrl: "https://x.test"));
    expect(find.text("REGARDER"), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _event(status: "scheduled"));
    expect(find.text("REGARDER"), findsNothing);
  });

  testWidgets("le score est dans la carte, entre les deux équipes (J21)", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 1));
    final score = tester.getCenter(find.text("2-1"));
    final a = tester.getCenter(find.text("G2 Esports"));
    final b = tester.getCenter(find.text("Paper Rex"));
    expect(score.dx, inExclusiveRange(a.dx, b.dx));
  });

  testWidgets("pourquoi ce match compte : mot souligné ouvre la feuille glossaire", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventProvider("evt-1").overrideWith((ref) async => _event(status: "scheduled", stakes: "Match en [[BO3]].")),
          userSettingProvider.overrideWith((ref) async => UserSettingDto((b) => b
            ..spoilerFree = false
            ..morningDigest = false)),
          overrideFollowsWith(const []),
          glossaryTermProvider("BO3").overrideWith(
            (ref) async => GlossaryTermDto((b) => b
              ..term = "bo3"
              ..text = "La première équipe qui gagne 2 cartes remporte le match."),
          ),
        ],
        child: const MaterialApp(home: NextMatchScreen(eventId: "evt-1")),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("Match en BO3.", findRichText: true), findsOneWidget);

    _tapSpan(tester, "BO3");
    await tester.pump();
    await tester.pump();

    expect(find.text("La première équipe qui gagne 2 cartes remporte le match."), findsOneWidget);
  });

  testWidgets("sans spoil, match terminé : score masqué puis révélé par appui long", (tester) async {
    await _pump(tester, _event(status: "finished", scoreA: 2, scoreB: 0), spoilerFree: true);

    // Le score est flouté (J11) : présent mais sous un `ImageFiltered`, tant qu'on ne maintient pas.
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.text("Maintiens pour révéler le score"), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.text("TERMINÉ")));
    // Le premier `pump` ne fait que démarrer l'horloge de l'animation : d'où la durée en plus.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text("2-0"), findsOneWidget);
  });

  testWidgets("forme récente : un nom de 5 lettres (TYLOO) tient sur une ligne", (tester) async {
    await _pump(tester, _event(status: "scheduled", shortNameA: "TYLOO"));

    final name = find.descendant(of: find.ancestor(of: find.text("FORME RÉCENTE"), matching: find.byType(Column)).first, matching: find.text("TYLOO"));
    expect(name, findsOneWidget);
    expect(tester.getSize(name).height, lessThan(24));
  });
}
