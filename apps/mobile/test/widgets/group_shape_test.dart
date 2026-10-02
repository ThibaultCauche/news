import "package:built_collection/built_collection.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile/widgets/group_bracket_tree.dart";
import "package:news_api_client/news_api_client.dart";

BracketNodeDto _node(String id, String name, num round, {String? startsAt}) => BracketNodeDto((b) => b
  ..eventId = id
  ..name = name
  ..status = "finished"
  ..round = round
  ..startsAt = startsAt
  ..participants = ListBuilder<BracketParticipantDto>());

BracketLinkDto _link(String from, String to, String outcome) => BracketLinkDto((b) => b
  ..fromEventId = from
  ..toEventId = to
  ..outcome = outcome);

BracketResponseDto _bracket(List<BracketNodeDto> nodes, List<BracketLinkDto> links) => BracketResponseDto((b) => b
  ..format = "groups_gsl"
  ..sourceUpdatedAt = "2026-10-02T00:00:00.000Z"
  ..nodes = ListBuilder<BracketNodeDto>(nodes)
  ..links = ListBuilder<BracketLinkDto>(links));

void main() {
  // Poule C de Champions 2026 telle que l'API du NAS la renvoyait : « TL vs PR » (une ouverture) n'a aucun
  // lien sortant (4 liens au lieu de 6) et se retrouve au tour 0, comme le Decider.
  test("poule GSL à un lien manquant : reconnue par les noms des matchs", () {
    final bracket = _bracket(
      [
        _node("o1", "TYLOO vs G2", 2, startsAt: "2026-09-24T09:00:00Z"),
        _node("o2", "TL vs PR", 0, startsAt: "2026-09-24T12:00:00Z"),
        _node("w", "Winners Match: G2 vs PR", 1),
        _node("e", "Elimination Match: TYLOO vs TL", 1),
        _node("d", "Decider Match: G2 vs TL", 0),
      ],
      [_link("o1", "w", "winner"), _link("o1", "e", "loser"), _link("w", "d", "loser"), _link("e", "d", "winner")],
    );

    final shape = detectGslShape(bracket);

    expect(shape, isNotNull);
    expect(shape!.winners.eventId, "w");
    expect(shape.elimination.eventId, "e");
    expect(shape.decider.eventId, "d");
    expect([shape.opening1.eventId, shape.opening2.eventId], ["o1", "o2"], reason: "ouvertures dans l'ordre de leur horaire");
  });

  test("poule GSL complète sans les noms habituels : repli sur les liens", () {
    final bracket = _bracket(
      [_node("o1", "A vs B", 2), _node("o2", "C vs D", 2), _node("m1", "Match 3", 1), _node("m2", "Match 4", 1), _node("d", "Match 5", 0)],
      [
        _link("o1", "m1", "winner"),
        _link("o2", "m1", "winner"),
        _link("o1", "m2", "loser"),
        _link("o2", "m2", "loser"),
        _link("m1", "d", "loser"),
        _link("m2", "d", "winner"),
      ],
    );

    final shape = detectGslShape(bracket);

    expect(shape?.winners.eventId, "m1");
    expect(shape?.elimination.eventId, "m2");
  });

  test("autre format (double élimination) : pas de forme GSL", () {
    final nodes = [for (var i = 0; i < 14; i++) _node("n$i", "Upper Bracket Quarterfinal $i", i % 5)];
    expect(detectGslShape(_bracket(nodes, const [])), isNull);
  });
}
