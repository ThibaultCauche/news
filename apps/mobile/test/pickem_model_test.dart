import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/pickem_model.dart";

void main() {
  championTests();
  realTeamsTests();
  final nodes = <PickemNode>[
    (id: "s1", participants: ["A", "B"], feeders: []),
    (id: "s2", participants: ["C", "D"], feeders: []),
    (id: "f", participants: [], feeders: [(fromId: "s1", winner: true), (fromId: "s2", winner: true)]),
    (id: "l", participants: [], feeders: [(fromId: "s1", winner: false), (fromId: "s2", winner: false)]),
  ];

  test("la finale se remplit des équipes choisies plus haut", () {
    final c = pickemCandidates(nodes, {"s1": "A", "s2": "D"});
    expect(c["f"], ["A", "D"]);
    expect(c["l"], ["B", "C"]);
    expect(pickemCandidates(nodes, {"s1": "A"})["f"], ["A"]);
  });

  test("changer un choix retire ceux qui en dépendaient", () {
    final before = {"s1": "A", "s2": "D", "f": "A"};
    expect(prunePickem(nodes, before), before);
    expect(prunePickem(nodes, {"s1": "B", "s2": "D", "f": "A"}), {"s1": "B", "s2": "D"});
  });
}

void championTests() {
  final nodes = <PickemNode>[
    (id: "s1", participants: ["A", "B"], feeders: []),
    (id: "s2", participants: ["C", "D"], feeders: []),
    (id: "f", participants: [], feeders: [(fromId: "s1", winner: true), (fromId: "s2", winner: true)]),
    (id: "l", participants: [], feeders: [(fromId: "s1", winner: false), (fromId: "s2", winner: false)]),
  ];
  test("un champion gagne tous ses matchs jusqu'à la finale", () {
    expect(championPath(nodes, "C"), {"s2": "C", "f": "C"});
    expect(championPath(nodes, "Z"), isEmpty);
  });
  test("les matchs se rangent par tour", () {
    expect(pickemRounds(nodes), {"s1": 0, "s2": 0, "f": 1, "l": 1});
  });
}

void realTeamsTests() {
  test("quand les deux équipes d'un match sont connues, ce sont elles seules qu'on peut choisir", () {
    final nodes = <PickemNode>[
      (id: "q1", participants: ["A", "B"], feeders: []),
      (id: "q2", participants: ["C", "D"], feeders: []),
      (id: "s", participants: ["A", "D"], feeders: [(fromId: "q1", winner: true), (fromId: "q2", winner: true)]),
    ];
    expect(pickemCandidates(nodes, {"q1": "B", "q2": "C"})["s"], ["A", "D"]);
  });
}
