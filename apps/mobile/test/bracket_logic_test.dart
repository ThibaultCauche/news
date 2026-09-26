import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_screen.dart";
import "package:news_api_client/news_api_client.dart";

BracketParticipantDto _participant({required String entityId, required String name, int? score, bool? isWinner}) {
  return BracketParticipantDto((b) => b
    ..entityId = entityId
    ..name = name
    ..shortName = name
    ..score = score
    ..isWinner = isWinner);
}

BracketNodeDto _node({
  required String eventId,
  required String name,
  String status = "scheduled",
  num round = 1,
  List<BracketParticipantDto> participants = const [],
}) {
  return BracketNodeDto((b) => b
    ..eventId = eventId
    ..name = name
    ..status = status
    ..round = round
    ..participants.addAll(participants));
}

BracketLinkDto _link({required String from, required String to, required String outcome}) {
  return BracketLinkDto((b) => b
    ..fromEventId = from
    ..toEventId = to
    ..outcome = outcome
    ..slot = 0);
}

void main() {
  group("highlightedEventIds", () {
    test("marque les matchs où participe une entité suivie", () {
      final g2 = _participant(entityId: "g2", name: "G2");
      final th = _participant(entityId: "th", name: "TH");
      final nodes = [
        _node(eventId: "qf1", name: "Upper Bracket Quarterfinal 1", participants: [g2, th]),
        _node(eventId: "qf2", name: "Upper Bracket Quarterfinal 2"), // TBD, pas de participants
      ];

      expect(highlightedEventIds(nodes, {"g2"}), {"qf1"});
    });

    test("aucune entité suivie : aucun match en or", () {
      final nodes = [_node(eventId: "qf1", name: "QF1", participants: [_participant(entityId: "g2", name: "G2")])];
      expect(highlightedEventIds(nodes, {}), isEmpty);
    });
  });

  group("bracketMatchRows", () {
    test("match résolu : une ligne par participant, avec score", () {
      final node = _node(
        eventId: "final",
        name: "Grand Final",
        status: "finished",
        round: 0,
        participants: [
          _participant(entityId: "g2", name: "G2 Esports", score: 3, isWinner: true),
          _participant(entityId: "fnc", name: "Fnatic", score: 1, isWinner: false),
        ],
      );
      final rows = bracketMatchRows(node, const [], {});
      expect(rows, [("G2 Esports", "3", true), ("Fnatic", "1", false)]);
    });

    test("match TBD avec liens entrants : placeholder « Perdant de »/« Gagnant de »", () {
      final qf1 = _node(
        eventId: "qf1",
        name: "Upper Bracket Quarterfinal 1",
        status: "finished",
        round: 2,
        participants: [
          _participant(entityId: "g2", name: "G2", isWinner: true),
          _participant(entityId: "th", name: "TH", isWinner: false),
        ],
      );
      final lower = _node(eventId: "lower1", name: "Lower Bracket Round 1 Match 1", round: 3);
      final byId = {"qf1": qf1, "lower1": lower};
      final incoming = [_link(from: "qf1", to: "lower1", outcome: "loser")];

      final rows = bracketMatchRows(lower, incoming, byId);
      expect(rows, [("Perdant de G2 vs TH", null, false)]);
    });

    test("lien entrant dont le match source n'existe pas encore : placeholder générique", () {
      final target = _node(eventId: "t", name: "Semifinal", round: 1);
      final rows = bracketMatchRows(target, [_link(from: "inconnu", to: "t", outcome: "winner")], {});
      expect(rows, [("Gagnant de un match à venir", null, false)]);
    });
  });
}
