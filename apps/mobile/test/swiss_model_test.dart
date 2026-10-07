import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_model.dart";
import "package:mobile/features/bracket/swiss_model.dart";
import "package:news_api_client/news_api_client.dart";

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

/// Huit équipes, trois rondes : A gagne tout (3-0), H perd tout (0-3).
BracketResponseDto _swiss() => BracketResponseDto((b) => b
  ..format = "swiss"
  ..sourceUpdatedAt = "2026-10-12T00:00:00Z"
  ..nodes.addAll([
    _m(1, "A", "B"), _m(1, "C", "D"), _m(1, "E", "F"), _m(1, "G", "H"),
    _m(2, "A", "C"), _m(2, "E", "G"), _m(2, "B", "D"), _m(2, "F", "H"),
    _m(3, "A", "E"), _m(3, "C", "G"), _m(3, "B", "F"), _m(3, "D", "H"),
  ]));

void main() {
  test("swissRoundOf lit le numéro de ronde dans le nom du match", () {
    expect(swissRoundOf("Round 3: G2 vs T1"), 3);
    expect(swissRoundOf("round 12"), 12);
    expect(swissRoundOf("Upper Bracket Final: G2 vs T1"), isNull);
  });

  test("buildSwissLayout range les matchs par ronde puis par bilan avant le match", () {
    final layout = buildSwissLayout(_swiss());
    expect(layout.rounds.map((r) => r.number), [1, 2, 3]);
    expect(layout.rounds[0].groups.map((g) => g.record), ["0-0"]);
    expect(layout.rounds[1].groups.map((g) => g.record), ["1-0", "0-1"]);
    expect(layout.rounds[2].groups.map((g) => g.record), ["2-0", "1-1", "0-2"]);
    expect(layout.rounds[2].groups[1].matches, hasLength(2));
  });

  test("trois victoires qualifient, trois défaites éliminent", () {
    final layout = buildSwissLayout(_swiss());
    expect(layout.qualified.map((t) => t.shortName), ["A"]);
    expect(layout.eliminated.map((t) => t.shortName), ["H"]);
  });

  test("une ronde pas encore jouée ne compte pour personne, et ses équipes inconnues vont dans « ? »", () {
    final bracket = _swiss().rebuild((b) => b
      ..nodes.add(BracketNodeDto((n) => n
        ..eventId = "r4-tbd"
        ..name = "Round 4: TBD vs TBD"
        ..status = "scheduled"
        ..round = 0)));
    final layout = buildSwissLayout(bracket);
    expect(layout.rounds.last.number, 4);
    expect(layout.rounds.last.groups.single.record, "?");
    expect(layout.qualified.map((t) => t.shortName), ["A"]);
  });

  test("les rondes de la phase suisse se nomment « Ronde N » dans l'appli", () {
    expect(stageOf("Round 2: G2 vs T1").title, "Ronde 2");
    expect(cardTitle("Round 5: G2 vs T1"), "Ronde 5");
  });
}
