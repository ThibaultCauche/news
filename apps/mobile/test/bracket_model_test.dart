import "package:flutter_test/flutter_test.dart";
import "package:mobile/features/bracket/bracket_model.dart";
import "package:news_api_client/news_api_client.dart";

BracketParticipantDto _p(String code, {int? score, bool? win}) => BracketParticipantDto((b) => b
  ..entityId = code.toLowerCase()
  ..name = code
  ..shortName = code
  ..score = score
  ..isWinner = win);

BracketNodeDto _n(String id, String name, int round, String status, {List<BracketParticipantDto> teams = const [], String? startsAt}) => BracketNodeDto((b) => b
  ..eventId = id
  ..name = name
  ..round = round
  ..status = status
  ..startsAt = startsAt
  ..participants.addAll(teams));

BracketLinkDto _l(String from, String to, String outcome) => BracketLinkDto((b) => b
  ..fromEventId = from
  ..toEventId = to
  ..outcome = outcome
  ..slot = 0);

/// Double élimination à 8 équipes, comme le tableau PandaScore de Champions. Quarts et
/// demies du haut jouées (G2 et FNC gagnent), finale du haut en direct, repêchage à venir.
BracketResponseDto _partial() => BracketResponseDto((b) => b
  ..format = "double_elim"
  ..sourceUpdatedAt = "2026-10-10T00:00:00Z"
  ..nodes.addAll([
    _n("q1", "Upper Bracket Quarterfinal 1: G2 vs DRX", 3, "finished", teams: [_p("G2", score: 2, win: true), _p("DRX", score: 0, win: false)]),
    _n("q2", "Upper Bracket Quarterfinal 2: PRX vs TL", 3, "finished", teams: [_p("PRX", score: 2, win: true), _p("TL", score: 1, win: false)]),
    _n("q3", "Upper Bracket Quarterfinal 3: FNC vs EDG", 3, "finished", teams: [_p("FNC", score: 2, win: true), _p("EDG", score: 0, win: false)]),
    _n("q4", "Upper Bracket Quarterfinal 4: TH vs SEN", 3, "finished", teams: [_p("TH", score: 2, win: true), _p("SEN", score: 1, win: false)]),
    _n("s1", "Upper Bracket Semifinal 1: G2 vs PRX", 2, "finished", teams: [_p("G2", score: 2, win: true), _p("PRX", score: 0, win: false)]),
    _n("s2", "Upper Bracket Semifinal 2: FNC vs TH", 2, "finished", teams: [_p("FNC", score: 2, win: true), _p("TH", score: 1, win: false)]),
    _n("uf", "Upper Bracket Final: FNC vs G2", 1, "live", teams: [_p("FNC", score: 1), _p("G2", score: 0)]),
    _n("lr1", "Lower Bracket Round 1 Match 1: TL vs DRX", 4, "scheduled", teams: [_p("TL"), _p("DRX")], startsAt: "2026-10-11T07:00:00Z"),
    _n("lf", "Lower Bracket Final: TBD vs TBD", 1, "scheduled"),
    _n("gf", "Grand Final: TBD vs TBD", 0, "scheduled", startsAt: "2026-10-18T15:00:00Z"),
  ])
  ..links.addAll([
    _l("q1", "s1", "winner"),
    _l("q2", "s1", "winner"),
    _l("q3", "s2", "winner"),
    _l("q4", "s2", "winner"),
    _l("s1", "uf", "winner"),
    _l("s2", "uf", "winner"),
    _l("q1", "lr1", "loser"),
    _l("q2", "lr1", "loser"),
    _l("uf", "gf", "winner"),
    _l("uf", "lf", "loser"),
    _l("lf", "gf", "winner"),
  ]));

bool _hasAncestor(TreeSlot slot, String matchId) {
  for (var p = slot.parent; p != null; p = p.parent) {
    if (p.matchId == matchId) return true;
  }
  return false;
}

void main() {
  group("stageOf", () {
    test("traduit les noms PandaScore", () {
      expect(stageOf("Upper Bracket Quarterfinal 1: TBD vs TBD").title, "Quart de finale 1");
      expect(stageOf("Upper Bracket Semifinal 2").title, "Demi-finale 2");
      expect(stageOf("Upper Bracket Final").title, "Finale du tableau principal");
      expect(stageOf("Lower Bracket Round 1 Match 2").title, "Repêchage, tour 1, match 2");
      expect(stageOf("Lower Bracket Quarterfinal 1").title, "Repêchage, quart de finale 1");
      expect(stageOf("Lower Bracket Semifinal").title, "Repêchage, demi-finale");
      expect(stageOf("Lower Bracket Final").title, "Finale du repêchage");
      expect(stageOf("Grand Final: TBD vs TBD").title, "Grande finale");
    });

    test("donne la forme avec « du / de la » et l'étiquette d'anneau", () {
      expect(stageOf("Upper Bracket Quarterfinal 1").de, "du quart de finale 1");
      expect(stageOf("Upper Bracket Semifinal 1").de, "de la demi-finale 1");
      expect(stageOf("Lower Bracket Quarterfinal 2").de, "du repêchage, quart de finale 2");
      expect(stageOf("Upper Bracket Quarterfinal 1").ring, "QUARTS");
      expect(stageOf("Upper Bracket Semifinal 1").ring, "DEMIES");
    });

    test("garde un nom inconnu tel quel", () {
      expect(stageOf("Open Finals - Division 1: TBD vs TBD").title, "Open Finals - Division 1");
    });
  });

  test("cardTitle : des titres qui tiennent sur une case", () {
    expect(cardTitle("Upper Bracket Final"), "Finale du haut");
    expect(cardTitle("Lower Bracket Quarterfinal 2"), "Repêchage · quart 2");
    expect(cardTitle("Lower Bracket Semifinal"), "Repêchage · demi");
    expect(cardTitle("Lower Bracket Round 1 Match 2"), "Repêchage · tour 1");
    expect(cardTitle("Upper Bracket Quarterfinal 3"), "Quart de finale 3");
  });

  group("placeholderLabel", () {
    test("nomme le match d'origine en français", () {
      final bracket = _partial();
      final byId = {for (final n in bracket.nodes) n.eventId: n};
      expect(placeholderLabel(_l("q1", "lr1", "loser"), byId), "Perdant du quart de finale 1");
      expect(placeholderLabel(_l("s1", "uf", "winner"), byId), "Gagnant de la demi-finale 1");
      expect(placeholderLabel(_l("zz", "uf", "winner"), byId), "Gagnant d'un match à venir");
    });
  });

  group("buildRadialTree", () {
    final tree = buildRadialTree(_partial());

    test("8 équipes à l'extérieur, 4 puis 2 vers le centre, finale au centre", () {
      expect(tree.center?.eventId, "gf");
      expect(tree.rings, 3);
      expect(tree.slots.where((s) => s.ring == 3), hasLength(8));
      expect(tree.slots.where((s) => s.ring == 2), hasLength(4));
      expect(tree.slots.where((s) => s.ring == 1), hasLength(2));
      expect(tree.ringLabels[3], "QUARTS");
      expect(tree.ringLabels[2], "DEMIES");
    });

    test("les équipes connues sont placées, les inconnues restent vides", () {
      final ring3 = tree.slots.where((s) => s.ring == 3).map((s) => s.team?.shortName).toList();
      expect(ring3, ["G2", "DRX", "PRX", "TL", "FNC", "EDG", "TH", "SEN"]);
      final ring2 = tree.slots.where((s) => s.ring == 2).map((s) => s.team?.shortName).toList();
      expect(ring2, ["G2", "PRX", "FNC", "TH"]);
      expect(tree.slots.where((s) => s.ring == 1).map((s) => s.team?.shortName), ["G2", "FNC"]);
    });

    test("un cercle prend l'angle moyen de ses deux entrées", () {
      for (final slot in tree.slots.where((s) => s.children.isNotEmpty)) {
        expect(slot.angle, closeTo((slot.children[0].angle + slot.children[1].angle) / 2, 1e-9));
      }
    });

    test("le perdant d'un match terminé est marqué", () {
      final drx = tree.slots.firstWhere((s) => s.ring == 3 && s.team?.shortName == "DRX");
      final g2 = tree.slots.firstWhere((s) => s.ring == 3 && s.team?.shortName == "G2");
      expect(drx.lost, isTrue);
      expect(g2.lost, isFalse);
    });

    test("le perdant d'une demi-finale terminée est marqué à l'anneau des demies", () {
      final prx = tree.slots.firstWhere((s) => s.ring == 2 && s.team?.shortName == "PRX");
      final g2 = tree.slots.firstWhere((s) => s.ring == 2 && s.team?.shortName == "G2");
      expect(prx.lost, isTrue);
      expect(g2.lost, isFalse);
    });

    test("bracket vide : pas de cercles, pas de plantage", () {
      final empty = buildRadialTree(BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.add(_n("gf", "Grand Final", 0, "scheduled"))));
      expect(empty.slots, isEmpty);
      expect(empty.center?.eventId, "gf");
    });
  });

  group("followedTeamLines", () {
    final now = DateTime.utc(2026, 10, 10, 12);

    test("match en direct : phrase et enjeu avec repêchage", () {
      final line = followedTeamLines(_partial(), {"g2"}, now).single;
      expect(line.headline, "G2 joue en ce moment : Finale du tableau principal.");
      expect(line.stakes, "Si G2 gagne, elle va en grande finale ; sinon elle passe au repêchage.");
      expect(line.matchId, "uf");
    });

    test("prochain match daté : jour et heure", () {
      final line = followedTeamLines(_partial(), {"tl"}, DateTime.utc(2026, 10, 10, 12)).single;
      expect(line.headline, startsWith("TL joue "));
      expect(line.headline, endsWith(": Repêchage, tour 1, match 1."));
    });

    test("équipe suivie hors du tableau : aucune phrase", () {
      expect(followedTeamLines(_partial(), {"zzz"}, now), isEmpty);
    });

    test("équipe éliminée du tableau final", () {
      final bracket = _partial().rebuild((b) => b
        ..nodes.replace([
          _n("lr1", "Lower Bracket Round 1 Match 1", 4, "finished", teams: [_p("TL", score: 0, win: false), _p("DRX", score: 2, win: true)]),
        ])
        ..links.clear());
      final line = followedTeamLines(bracket, {"tl"}, now).single;
      expect(line.headline, "TL est éliminée du tournoi.");
      expect(line.stakes, isNull);
    });

    test("champion", () {
      final bracket = _partial().rebuild((b) => b
        ..nodes.replace([
          _n("gf", "Grand Final", 0, "finished", teams: [_p("G2", score: 3, win: true), _p("FNC", score: 1, win: false)]),
        ])
        ..links.clear());
      expect(followedTeamLines(bracket, {"g2"}, now).single.headline, "G2 est championne.");
    });
  });

  group("buildGridLayout", () {
    final layout = buildGridLayout(_partial());
    GridCell cell(String id) => layout.cell(id)!;

    test("colonnes = tours du chemin des gagnants : quarts, demies, finale du haut, grande finale", () {
      expect([cell("q1").col, cell("q4").col, cell("s1").col, cell("uf").col], [0, 0, 1, 2]);
      // Le 1er tour du repêchage, fait de perdants seulement, est dans la 1re colonne.
      expect(cell("lr1").col, 0);
      expect(cell("gf").col, greaterThan(cell("uf").col));
      expect(cell("gf").col, greaterThan(cell("lf").col));
    });

    test("un match d'arrivée se place entre ses deux sources", () {
      expect(cell("s1").row, closeTo((cell("q1").row + cell("q2").row) / 2, 1e-9));
      expect(cell("uf").row, closeTo((cell("s1").row + cell("s2").row) / 2, 1e-9));
    });

    test("le repêchage est une bande sous le tableau principal", () {
      final mainMax = ["q1", "q2", "q3", "q4", "s1", "s2", "uf"].map((id) => cell(id).row).reduce((a, b) => a > b ? a : b);
      expect(cell("lr1").row, greaterThan(mainMax));
      expect(cell("lf").row, greaterThan(mainMax));
    });

    test("la grande finale est entre la finale du haut et celle du repêchage", () {
      expect(cell("gf").row, closeTo((cell("uf").row + cell("lf").row) / 2, 1e-9));
    });

    test("deux matchs d'une même colonne ne se chevauchent pas", () {
      for (final a in layout.cells) {
        for (final b in layout.cells) {
          if (a != b && a.col == b.col) expect((a.row - b.row).abs(), greaterThanOrEqualTo(1 - 1e-9));
        }
      }
    });

    test("poule GSL : l'élimination est dans la 1re colonne, le décisif dans la 2e", () {
      BracketNodeDto node(String id, String name) => _n(id, name, 0, "scheduled");
      final gsl = BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.addAll([node("o1", "Opening Match 1"), node("o2", "Opening Match 2"), node("w", "Winners Match"), node("e", "Elimination Match"), node("d", "Decider Match")])
        ..links.addAll([
          _l("o1", "w", "winner"),
          _l("o2", "w", "winner"),
          _l("o1", "e", "loser"),
          _l("o2", "e", "loser"),
          _l("w", "d", "loser"),
          _l("e", "d", "winner"),
        ]));
      final g = buildGridLayout(gsl);
      expect([g.cell("o1")!.col, g.cell("w")!.col, g.cell("e")!.col, g.cell("d")!.col], [0, 1, 0, 1]);
      expect(g.cell("e")!.row, greaterThan(g.cell("o2")!.row));
      expect(g.cell("d")!.row, greaterThan(g.cell("w")!.row));
    });
  });

  group("nextMatchId", () {
    test("le match en direct d'abord", () {
      expect(nextMatchId(_partial(), {}), "uf");
    });

    test("sinon le prochain d'une équipe suivie, sinon le plus proche", () {
      final noLive = _partial().rebuild((b) => b..nodes.map((n) => n.eventId == "uf" ? n.rebuild((x) => x..status = "scheduled") : n));
      expect(nextMatchId(noLive, {"tl"}), "lr1");
      expect(nextMatchId(noLive, {}), "lr1"); // le plus proche daté
    });

    test("tout est terminé : rien à mettre en avant", () {
      final done = BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.add(_n("gf", "Grand Final", 0, "finished")));
      expect(nextMatchId(done, {}), isNull);
    });

    test("tout est terminé : la vue se pose sur le dernier match joué", () {
      final done = BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.addAll([_n("sf", "Semifinal 1", 1, "finished"), _n("gf", "Grand Final", 0, "finished")]));
      expect(anchorMatchId(done, {}), isNotNull);
      expect(anchorMatchId(_partial(), {}), "uf"); // sinon le prochain match
    });
  });

  group("assignSectors", () {
    test("chaque branche reste dans son secteur, un cercle intérieur à l'angle moyen de ses entrées", () {
      final tree = buildRadialTree(_partial());
      // Les quarts de la 1re demi-finale en haut, ceux de la 2e en bas : on teste le principe sur le tableau du haut.
      final heads = tree.slots.where((s) => s.parent == null).map((s) => s.matchId).toSet().toList();
      assignSectors(tree, {heads.first: (-3.0, 0.0)});
      final branch = tree.slots.where((s) => s.matchId == heads.first || _hasAncestor(s, heads.first)).toList();
      for (final slot in branch) {
        expect(slot.angle, inInclusiveRange(-3.0, 0.0));
        if (slot.children.isNotEmpty) expect(slot.angle, closeTo((slot.children[0].angle + slot.children[1].angle) / 2, 1e-9));
      }
    });
  });

  group("cercle avec repêchage", () {
    test("le tableau principal en haut, le repêchage en bas, le perdant de la finale du haut entre au repêchage", () {
      final bracket = _partial();
      final tree = buildRadialTree(bracket, includeLower: true, loserTargets: {"lf"});
      final halves = mainAndLowerHalves(tree, bracket)!;
      assignSectors(tree, halves);

      final lowerSlots = tree.slots.where((s) => s.matchId == "lf").toList();
      final upperSlots = tree.slots.where((s) => s.matchId == "uf").toList();
      expect(lowerSlots, hasLength(2));
      for (final s in lowerSlots) {
        expect(s.angle, inInclusiveRange(0, 3.1416));
      }
      for (final s in upperSlots) {
        expect(s.angle, inInclusiveRange(-3.1416, 0));
      }
      // Le perdant de la finale du haut (en cours : personne encore) laisse un cercle vide à entrer au repêchage.
      expect(lowerSlots.map((s) => s.team), everyElement(isNull));
    });

    test("l'entrée du perdant de la finale du haut peut être omise", () {
      final tree = buildRadialTree(_partial(), includeLower: true, loserTargets: {}, omitLeaves: {"lf"});
      expect(tree.slots.where((s) => s.matchId == "lf"), isEmpty);
      expect(lowerFinalId(_partial()), "lf");
    });

    test("sans repêchage : pas de moitiés", () {
      final bracket = BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.addAll([_n("f", "Final", 0, "scheduled"), _n("s1", "Semifinal 1", 1, "scheduled"), _n("s2", "Semifinal 2", 1, "scheduled")])
        ..links.addAll([_l("s1", "f", "winner"), _l("s2", "f", "winner")]));
      expect(mainAndLowerHalves(buildRadialTree(bracket), bracket), isNull);
    });

    test("un perdant qui entre au repêchage porte ses deux anciennes équipes (poule)", () {
      final gsl = BracketResponseDto((b) => b
        ..sourceUpdatedAt = "x"
        ..nodes.addAll([
          _n("q", "Qualified", 0, "scheduled"),
          _n("w", "Winners Match", 1, "finished", teams: [_p("PR", win: true), _p("G2", win: false)]),
          _n("d", "Decider Match", 1, "scheduled"),
        ])
        ..links.addAll([_l("w", "q", "winner"), _l("d", "q", "winner"), _l("w", "d", "loser")]));
      final tree = buildRadialTree(gsl, loserTargets: {"d"}, loserExpandsSides: true);
      final under = tree.slots.where((s) => s.ring == 2).toList();
      expect(under.map((s) => s.team?.shortName), ["PR", "G2"]);
      // Ces deux équipes gardent leur place (symétrie) mais ne sont pas dessinées : leur match est déjà dans l'autre moitié.
      expect(under.every((s) => s.hidden), isTrue);
      // Le perdant (G2) est celui qui avance vers le décisif.
      expect(under.firstWhere((s) => s.team?.shortName == "G2").advances, isTrue);
      expect(under.firstWhere((s) => s.team?.shortName == "PR").advances, isFalse);
    });
  });

  test("un cercle est toujours centré sur la barre de ses deux entrées, même d'une branche déséquilibrée", () {
    // q ← m1 (côté X nourri par m2, côté W seul) ; m2 (côté Y nourri par m3, côté Z seul) ; m3 (deux équipes).
    final bracket = BracketResponseDto((b) => b
      ..sourceUpdatedAt = "x"
      ..nodes.addAll([_n("q", "Final", 0, "scheduled"), _n("m1", "Match 1", 1, "scheduled"), _n("m2", "Match 2", 2, "scheduled"), _n("m3", "Match 3", 3, "scheduled")])
      ..links.addAll([_l("m3", "m2", "winner"), _l("m2", "m1", "winner"), _l("m1", "q", "winner")]));
    final tree = buildRadialTree(bracket);
    for (final slot in tree.slots.where((s) => s.children.isNotEmpty)) {
      expect(slot.angle, closeTo(slot.children.map((c) => c.angle).reduce((a, b) => a + b) / slot.children.length, 1e-9));
    }
  });

  test("repêchage en miroir : chaque cercle du bas a son reflet de l'autre côté de la verticale", () {
    // gf ← lf ← ls ← (lq1 ← lr1, lq2 ← lr2) ; chaque lq a, en plus de son lr, une entrée venue d'ailleurs.
    final bracket = BracketResponseDto((b) => b
      ..sourceUpdatedAt = "x"
      ..nodes.addAll([
        _n("gf", "Grand Final", 0, "scheduled"),
        _n("lf", "Lower Bracket Final", 1, "scheduled"),
        _n("ls", "Lower Bracket Semifinal", 2, "scheduled"),
        _n("lq1", "Lower Bracket Quarterfinal 1", 3, "scheduled"),
        _n("lq2", "Lower Bracket Quarterfinal 2", 3, "scheduled"),
        _n("lr1", "Lower Bracket Round 1 Match 1", 4, "scheduled"),
        _n("lr2", "Lower Bracket Round 1 Match 2", 4, "scheduled"),
      ])
      ..links.addAll([_l("lf", "gf", "winner"), _l("ls", "lf", "winner"), _l("lq1", "ls", "winner"), _l("lq2", "ls", "winner"), _l("lr1", "lq1", "winner"), _l("lr2", "lq2", "winner")]));
    final tree = buildRadialTree(bracket, includeLower: true, omitLeaves: {"lf"});
    assignSectors(tree, {"lf": (0.0, 3.141592653589793)}, mirrored: {"lf"});
    String key(TreeSlot s, double angle) => "${s.ring}@${(angle * 1000).round()}";
    final angles = {for (final s in tree.slots) key(s, s.angle)};
    final mirrors = {for (final s in tree.slots) key(s, 3.141592653589793 - s.angle)};
    expect(angles, mirrors);
    // Le cercle de tête est pile en bas, au milieu de la moitié.
    expect(tree.slots.firstWhere((s) => s.ring == 1).angle, closeTo(3.141592653589793 / 2, 1e-9));
  });

  group("liveGroupsFirst", () {
    test("la poule qui joue d'abord, puis l'ordre alphabétique", () {
      expect(liveGroupsFirst(["A", "B", "C", "D"], {"C"}), ["C", "A", "B", "D"]);
      expect(liveGroupsFirst(["A", "B", "C", "D"], {"D", "B"}), ["B", "D", "A", "C"]);
    });

    test("aucune poule en direct : l'ordre reçu", () {
      expect(liveGroupsFirst(["A", "B", "C"], {}), ["A", "B", "C"]);
    });
  });

  group("defaultBracketTab", () {
    BracketResponseDto bracket(List<String> statuses) => BracketResponseDto((b) => b
      ..sourceUpdatedAt = "x"
      ..nodes.addAll([for (final (i, st) in statuses.indexed) _n("n$i", "Match $i", 0, st)]));

    test("poules en cours : Groupes", () {
      expect(defaultBracketTab(groups: [bracket(["finished", "live"]), bracket(["finished"])], playoffs: bracket(["scheduled"])), 0);
    });

    test("toutes les poules terminées : Phase finale, même avant le premier match", () {
      expect(defaultBracketTab(groups: [bracket(["finished"]), bracket(["finished", "finished"])], playoffs: bracket(["scheduled", "scheduled"])), 1);
    });

    test("la phase finale a commencé : Phase finale", () {
      expect(defaultBracketTab(groups: [bracket(["live"])], playoffs: bracket(["live"])), 1);
    });

    test("pas de poules du tout : Phase finale directement", () {
      expect(defaultBracketTab(groups: [], playoffs: bracket(["scheduled"])), 1);
    });

    test("pas de phase finale connue, ou poules pas encore chargées : Groupes", () {
      expect(defaultBracketTab(groups: [bracket(["finished"])], playoffs: null), 0);
      expect(defaultBracketTab(groups: [null], playoffs: bracket(["scheduled"])), 0);
    });
  });

  test("scheduleLabel", () {
    final now = DateTime(2026, 10, 10, 12);
    expect(scheduleLabel(DateTime(2026, 10, 10, 21, 30), now), "aujourd'hui à 21 h 30");
    expect(scheduleLabel(DateTime(2026, 10, 11, 9), now), "demain à 9 h");
    expect(scheduleLabel(DateTime(2026, 10, 18, 17), now), "le 18 octobre à 17 h");
  });
}
