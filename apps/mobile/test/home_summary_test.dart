import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/home/home_screen.dart";
import "package:news_api_client/news_api_client.dart";

EventSummaryDto _match(String id, String status, DateTime startsAt) => EventSummaryDto((e) => e
  ..id = id
  ..kind = "match"
  ..name = "FNC vs G2"
  ..status = status
  ..startsAt = startsAt.toUtc().toIso8601String()
  ..bestOf = 3
  ..importance = 1
  ..competition.replace(CompetitionRefDto((c) => c
    ..id = "c"
    ..name = "Champions"))
  ..participants.addAll([
    EventParticipantDto((p) => p
      ..entityId = "fnc"
      ..name = "Fnatic"
      ..shortName = "FNC"),
    EventParticipantDto((p) => p
      ..entityId = "g2"
      ..name = "G2 Esports"
      ..shortName = "G2"),
  ]));

HomeResponseDto _home({List<EventSummaryDto> live = const [], List<EventSummaryDto> upcoming = const [], EventSummaryDto? mine}) => HomeResponseDto((b) {
      b
        ..sourceUpdatedAt = "2026-10-10T00:00:00Z"
        ..liveNow.addAll(live)
        ..upcoming.addAll(upcoming);
      if (mine != null) b.nowForYou.replace(mine);
    });

void main() {
  final now = DateTime(2026, 10, 10, 12);

  test("rien à dire : pas de ligne", () {
    expect(homeSummary(_home(), now), isNull);
  });

  test("ton match en direct", () {
    final live = _match("a", "live", now);
    expect(homeSummary(_home(live: [live], mine: live), now), "Ton match est en direct : FNC – G2.");
  });

  test("une session de F1 se nomme par son Grand Prix, pas par des équipes (J28)", () {
    final session = EventSummaryDto((e) => e
      ..id = "s"
      ..kind = "session"
      ..name = "Essais libres 1"
      ..status = "scheduled"
      ..startsAt = DateTime(2026, 10, 11, 9).toUtc().toIso8601String()
      ..importance = 0
      ..competition.replace(CompetitionRefDto((c) => c
        ..id = "gp"
        ..name = "Singapore Grand Prix"
        ..game = "formula-1")));
    expect(homeSummary(_home(upcoming: [session], mine: session), now), "Ton prochain match : Grand Prix de Singapour (Essais libres 1), demain à 9 h.");
  });

  test("ton prochain match, avec le jour et l'heure", () {
    final next = _match("a", "scheduled", DateTime(2026, 10, 11, 9));
    expect(homeSummary(_home(upcoming: [next], mine: next), now), "Ton prochain match : FNC – G2, demain à 9 h.");
  });

  test("sans suivi : nombre de matchs en direct, sinon du jour", () {
    expect(homeSummary(_home(live: [_match("a", "live", now), _match("b", "live", now)]), now), "2 matchs en direct.");
    expect(homeSummary(_home(upcoming: [_match("a", "scheduled", DateTime(2026, 10, 10, 20))]), now), "1 match aujourd'hui.");
    expect(homeSummary(_home(upcoming: [_match("a", "scheduled", DateTime(2026, 10, 12, 20))]), now), isNull);
  });
}
