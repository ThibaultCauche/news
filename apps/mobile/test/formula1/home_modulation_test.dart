import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:mobile/features/home/home_modulation.dart";
import "package:news_api_client/news_api_client.dart";

MajorCompetitionDto _major(String name, String game, {bool live = false}) => MajorCompetitionDto((b) => b
  ..id = name
  ..name = name
  ..game = game
  ..live = live);

HomeSuggestionDto _suggestion({bool live = false, String? startsAt}) => HomeSuggestionDto((b) => b
  ..category = "sport"
  ..categoryName = "Sport"
  ..competitionId = "f1"
  ..competitionName = "Formule 1 2026"
  ..game = "formula-1"
  ..live = live
  ..startsAt = startsAt);

void main() {
  setUpAll(() => initializeDateFormatting("fr_FR"));

  test("les grands rendez-vous de la catégorie favorite passent devant, l'ordre du serveur est gardé", () {
    final majors = [_major("Champions", "valorant"), _major("Worlds", "league-of-legends"), _major("F1", "formula-1"), _major("Masters", "valorant")];
    expect(orderMajorsFor("sport", majors).map((m) => m.name), ["F1", "Champions", "Worlds", "Masters"]);
    expect(orderMajorsFor("esport", majors).map((m) => m.name), ["Champions", "Worlds", "Masters", "F1"]);
    expect(orderMajorsFor(null, majors).map((m) => m.name), ["Champions", "Worlds", "F1", "Masters"]);
  });

  test("la suggestion disparaît 7 jours après avoir été fermée", () {
    final now = DateTime(2026, 10, 8, 12);
    expect(suggestionVisible(null, now), isTrue);
    expect(suggestionVisible(now.subtract(const Duration(days: 3)), now), isFalse);
    expect(suggestionVisible(now.subtract(const Duration(days: 7)), now), isTrue);
  });

  test("la phrase dit si le rendez-vous est en cours ou quand il commence", () {
    final now = DateTime(2026, 10, 8, 12);
    expect(suggestionSentence(_suggestion(live: true), now), "Formule 1 2026 est en cours.");
    expect(suggestionSentence(_suggestion(), now), "Formule 1 2026 arrive bientôt.");
    expect(suggestionSentence(_suggestion(startsAt: DateTime(2026, 10, 9, 10, 30).toUtc().toIso8601String()), now), startsWith("Formule 1 2026 commence demain"));
  });
}
