import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/formula1/f1_model.dart";
import "package:news_api_client/news_api_client.dart";

ClassificationRowDto _row({int position = 1, String? positionText, String? time, String? status, int? laps, String? q1, String? q2, String? q3}) => ClassificationRowDto((b) => b
  ..laps = laps?.toDouble()
  ..entityId = "d$position"
  ..position = position
  ..positionText = positionText ?? "$position"
  ..name = "Pilote $position"
  ..time = time
  ..status = status
  ..q1 = q1
  ..q2 = q2
  ..q3 = q3);

void main() {
  test("traduit les Grands Prix connus et garde le nom d'origine des autres", () {
    expect(grandPrixName("Australian Grand Prix"), "Grand Prix d'Australie");
    expect(grandPrixName("United States Grand Prix"), "Grand Prix des États-Unis");
    expect(grandPrixName("Bahrain Grand Prix in Malaysia"), "Bahrain Grand Prix in Malaysia");
    expect(grandPrixName("Inconnu Grand Prix"), "Inconnu Grand Prix");
  });

  test("le podium suit la position, pas l'ordre reçu", () {
    EventParticipantDto p(String code, int score) => EventParticipantDto((b) => b
      ..entityId = code
      ..name = "Pilote $code"
      ..shortName = code
      ..score = score);
    expect(podiumLabel([p("LEC", 3), p("RUS", 1), p("ANT", 2)]), "RUS · ANT · LEC");
    expect(podiumLabel([]), "");
  });

  test("lit une position, un écart et une cause d'abandon", () {
    expect(positionLabel(_row(position: 4, positionText: "R")), "Ab.");
    expect(positionLabel(_row(position: 2)), "2");
    expect(gapLabel(_row(time: "+2.974")), "+2.974");
    expect(gapLabel(_row(status: "+2 Laps")), "+2 tours");
    expect(gapLabel(_row(status: "+1 Lap")), "+1 tour");
    expect(gapLabel(_row(status: "Engine")), "Moteur");
    expect(gapLabel(_row(status: "Finished")), "");
  });

  test("un pilote doublé affiche ses tours de retard, pas l'écart avec la voiture de son tour", () {
    // Jolpica donne « +4.593 » à un pilote à un tour du vainqueur : c'est l'écart avec la première voiture de son tour.
    expect(gapLabel(_row(position: 7, time: "+4.593", status: "Lapped", laps: 57), winnerLaps: 58), "+1 tour");
    expect(gapLabel(_row(position: 14, time: "+8.487", status: "Lapped", laps: 56), winnerLaps: 58), "+2 tours");
    expect(gapLabel(_row(position: 2, time: "+2.974", status: "Finished", laps: 58), winnerLaps: 58), "+2.974");
    // Un abandon classé « doublé » par la source reste un abandon.
    expect(gapLabel(_row(position: 17, positionText: "R", status: "Lapped", laps: 43), winnerLaps: 58), "Abandon");
  });

  test("les qualifications montrent le dernier tour réalisé", () {
    expect(qualifyingTime(_row(q1: "1:20.0", q2: "1:19.5", q3: "1:19.1")), "1:19.1");
    expect(qualifyingTime(_row(q1: "1:20.0")), "1:20.0");
    expect(isQualifying("Qualifications sprint"), isTrue);
    expect(hasClassification("Essais libres 2"), isFalse);
    expect(hasClassification("Course"), isTrue);
  });
}
