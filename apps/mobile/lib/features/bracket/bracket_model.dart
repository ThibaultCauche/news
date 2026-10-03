import "dart:math" as math;
import "package:news_api_client/news_api_client.dart";
import "../../core/iterable_x.dart";

/// Logique pure de l'arbre de la phase finale (J20, aucun widget) : noms de matchs en
/// français, placement des équipes sur l'arbre radial, phrases d'enjeu par gabarit.
/// Tout est dérivé de `BracketResponseDto` (`/v1/competitions/:id/bracket`) : l'API n'a
/// pas changé.

/// Nom du match sans le suffixe « : TBD vs TBD » que PandaScore ajoute.
String _bare(String apiName) => apiName.split(":").first.trim();

bool isLowerBracketName(String apiName) => apiName.toLowerCase().contains("lower bracket");

/// Nom français d'un match PandaScore. `title` : « Quart de finale 1 » ; `de` : « du
/// quart de finale 1 » (pour « Perdant du quart de finale 1 ») ; `ring` : étiquette de
/// l'anneau de l'arbre (« QUARTS »).
typedef Stage = ({String title, String de, String ring});

Stage stageOf(String apiName) {
  final name = _bare(apiName).toLowerCase();
  final n = RegExp(r"(\d+)\s*$").firstMatch(name)?.group(1);
  final suffix = n == null ? "" : " $n";
  final isLower = name.contains("lower bracket");
  final base = name.replaceFirst(RegExp(r"^(upper|lower) bracket\s*"), "").replaceFirst(RegExp(r"\s*\d+\s*$"), "").trim();

  if (name.startsWith("opening match")) return (title: "Ouverture$suffix", de: "de l'ouverture$suffix", ring: "OUVERTURE");
  if (name.startsWith("winners")) return (title: "Match des vainqueurs", de: "du match des vainqueurs", ring: "VAINQUEURS");
  if (name.startsWith("elimination")) return (title: "Match d'élimination", de: "du match d'élimination", ring: "ÉLIMINATION");
  if (name.startsWith("decider")) return (title: "Match décisif", de: "du match décisif", ring: "DECIDER");
  if (name.startsWith("grand final")) return (title: "Grande finale", de: "de la grande finale", ring: "FINALE");
  if (isLower && base.startsWith("round")) {
    final round = RegExp(r"round (\d+)").firstMatch(name)?.group(1) ?? "";
    final match = RegExp(r"match (\d+)").firstMatch(name)?.group(1);
    final tail = match == null ? "" : ", match $match";
    return (title: "Repêchage, tour $round$tail", de: "du repêchage, tour $round$tail", ring: "TOUR $round");
  }
  final (title, de, ring) = switch (base) {
    "quarterfinal" => ("Quart de finale$suffix", "du quart de finale$suffix", "QUARTS"),
    "semifinal" => ("Demi-finale$suffix", "de la demi-finale$suffix", "DEMIES"),
    "final" => isLower ? ("Finale du repêchage", "de la finale du repêchage", "FINALE") : ("Finale du tableau principal", "de la finale du tableau principal", "FINALE"),
    _ => (_bare(apiName), "de ${_bare(apiName)}", ""),
  };
  if (isLower && base != "final") return (title: "Repêchage, ${title.toLowerCase()}", de: "du repêchage, ${de.replaceFirst(RegExp(r"^(du|de la) "), "")}", ring: ring);
  return (title: title, de: de, ring: ring);
}

/// Titre d'une case de la pyramide : le même, en plus court (une case fait 176 px de large).
String cardTitle(String apiName) => stageOf(apiName)
    .title
    .replaceFirst("Finale du tableau principal", "Finale du haut")
    .replaceFirstMapped(RegExp(r"^Repêchage, quart de finale (\d+)"), (m) => "Repêchage · quart ${m[1]}")
    .replaceFirst("Repêchage, demi-finale", "Repêchage · demi")
    .replaceFirstMapped(RegExp(r"^Repêchage, tour (\d+).*"), (m) => "Repêchage · tour ${m[1]}");

/// « Perdant du quart de finale 1 » / « Gagnant de la demi-finale 2 », pour un match dont
/// les équipes ne sont pas encore connues.
String placeholderLabel(BracketLinkDto link, Map<String, BracketNodeDto> byId) {
  final verb = link.outcome == "winner" ? "Gagnant" : "Perdant";
  final from = byId[link.fromEventId];
  if (from == null) return "$verb d'un match à venir";
  return "$verb ${stageOf(from.name).de}";
}

BracketParticipantDto? winnerOf(BracketNodeDto node) => node.participants.firstWhereOrNull((p) => p.isWinner == true);

bool _isFinished(BracketNodeDto n) => n.status == "finished";

String teamCode(BracketParticipantDto p) => p.shortName ?? p.name.substring(0, math.min(3, p.name.length)).toUpperCase();

// ─── Arbre radial ──────────────────────────────────────────────────────────

/// Un cercle de l'arbre : une équipe (connue ou non) à l'entrée d'un match.
class TreeSlot {
  TreeSlot({required this.ring, required this.matchId, required this.team, required this.lost, required this.won, required this.advances, required this.live, this.score, this.parent, this.hidden = false});

  /// 1 = anneau intérieur, croissant vers l'extérieur.
  final int ring;

  /// Le match que ce cercle va jouer (ou a joué) : cible d'un appui.
  final String matchId;
  final BracketParticipantDto? team;

  /// Son match est terminé et elle l'a perdu (elle continue peut-être au repêchage).
  final bool lost;

  /// Son match est terminé et elle l'a gagné : elle avance vers [parent].
  final bool won;

  /// Elle avance vers [parent] : en gagnant, ou en perdant quand [parent] est « le perdant de ce match ».
  final bool advances;

  /// Place réservée mais rien à dessiner : garde la symétrie du cercle sans remettre à l'écran un match déjà montré ailleurs.
  final bool hidden;

  /// Son match est en direct, avec le score de série de cette équipe.
  final bool live;
  final int? score;

  /// Le cercle où va le vainqueur de [matchId] ; `null` = le centre.
  TreeSlot? parent;
  final List<TreeSlot> children = [];
  double angle = 0;

  /// Nombre d'anneaux de sa branche quand le cercle est coupé en deux (0 = ceux de tout l'arbre) :
  /// chaque moitié répartit ses anneaux sur tout le rayon, même si l'autre en a plus.
  int branchRings = 0;
}

class RadialTree {
  RadialTree({required this.center, required this.slots, required this.rings, required this.ringLabels});

  /// Le match décisif, au centre. `null` si le bracket est vide.
  final BracketNodeDto? center;
  final List<TreeSlot> slots;
  final int rings;

  /// Étiquette de l'anneau (« QUARTS »), indexée par numéro d'anneau.
  final Map<int, String> ringLabels;
}

/// Un match qui alimente un autre : son gagnant (lien « winner ») ou son perdant (lien « loser »).
class _Pred {
  const _Pred(this.node, {required this.loser});
  final BracketNodeDto node;
  final bool loser;

  BracketParticipantDto? get team => loser ? loserOf(node) : winnerOf(node);
}

BracketParticipantDto? loserOf(BracketNodeDto node) => node.participants.firstWhereOrNull((p) => p.isWinner == false);

/// [includeLower] : le repêchage fait aussi partie de l'arbre (la moitié du bas du cercle).
/// [loserTargets] : les matchs dont les liens « perdant » comptent (un perdant du tableau principal
/// y entre comme un cercle de plus). [loserExpandsSides] : ce perdant s'accompagne alors des deux
/// équipes du match qu'il vient de perdre (la poule : le décisif reçoit le perdant du match des
/// vainqueurs ; ces deux équipes gardent leur place mais ne sont pas dessinées : leur match est déjà
/// dans l'autre moitié). [omitLeaves] : les matchs dont les équipes qui ne viennent d'aucun match
/// de l'arbre (le perdant de la finale du haut, qui rejoint la finale du repêchage) sont omises.
RadialTree buildRadialTree(BracketResponseDto bracket, {bool includeLower = false, Set<String> loserTargets = const {}, bool loserExpandsSides = false, Set<String> omitLeaves = const {}}) {
  final nodes = bracket.nodes.where((n) => includeLower || !isLowerBracketName(n.name)).toList();
  final byId = {for (final n in nodes) n.eventId: n};
  final predecessors = <String, List<_Pred>>{};
  for (final l in bracket.links) {
    final from = byId[l.fromEventId];
    if (from == null || !byId.containsKey(l.toEventId)) continue;
    final loser = l.outcome != "winner";
    if (loser && !loserTargets.contains(l.toEventId)) continue;
    predecessors.putIfAbsent(l.toEventId, () => []).add(_Pred(from, loser: loser));
  }
  // Ordre stable (« demi-finale 1 » avant « demi-finale 2 »), pas celui de `slot`.
  for (final list in predecessors.values) {
    list.sort((a, b) => _bare(a.node.name).compareTo(_bare(b.node.name)));
  }

  final root = nodes.firstWhereOrNull((n) => n.round == 0);
  if (root == null) return RadialTree(center: null, slots: [], rings: 0, ringLabels: {});

  final slots = <TreeSlot>[];
  final ringLabels = <int, String>{};
  var maxRing = 0;

  TreeSlot addSlot(BracketNodeDto match, int ring, BracketParticipantDto? team, TreeSlot? parent, {required bool viaLoser, bool hidden = false}) {
    // Le résultat de CE match (celui du cercle), pas celui du match d'où vient l'équipe.
    final current = team == null ? null : match.participants.firstWhereOrNull((p) => p.entityId == team.entityId);
    final lost = _isFinished(match) && current?.isWinner == false;
    final won = _isFinished(match) && current?.isWinner == true;
    final slot = TreeSlot(
      ring: ring,
      matchId: match.eventId,
      team: team,
      lost: lost,
      won: won,
      // Elle avance vers [parent] en gagnant, ou en perdant quand le cercle d'au-dessus est « le perdant de ce match ».
      advances: viaLoser ? lost : won,
      live: match.status == "live",
      score: current?.score?.toInt(),
      parent: parent,
      hidden: hidden,
    );
    parent?.children.add(slot);
    slots.add(slot);
    maxRing = math.max(maxRing, ring);
    return slot;
  }

  // Les deux cercles d'un match, chacun rattaché à [parent] (là où va le vainqueur).
  void expand(BracketNodeDto match, int ring, TreeSlot? parent, {bool viaLoser = false}) {
    maxRing = math.max(maxRing, ring);
    final label = stageOf(match.name).ring;
    // Plusieurs branches peuvent partager un anneau (les poules) : leurs étiquettes se joignent.
    if (label.isNotEmpty) ringLabels.update(ring, (v) => v.split(" · ").contains(label) ? v : "$v · $label", ifAbsent: () => label);
    final preds = predecessors[match.eventId] ?? const <_Pred>[];
    final fedIds = {for (final p in preds) p.team?.entityId}..remove(null);
    final leafTeams = match.participants.where((p) => !fedIds.contains(p.entityId)).toList();
    var leaf = 0;
    for (var side = 0; side < 2; side++) {
      final pred = side < preds.length ? preds[side] : null;
      if (pred == null && omitLeaves.contains(match.eventId)) continue;
      final team = pred != null ? pred.team : (leaf < leafTeams.length ? leafTeams[leaf++] : null);
      final slot = addSlot(match, ring, team, parent, viaLoser: viaLoser);
      if (pred == null) continue;
      if (!pred.loser) {
        expand(pred.node, ring + 1, slot);
      } else if (loserExpandsSides) {
        for (var s = 0; s < 2; s++) {
          final p = s < pred.node.participants.length ? pred.node.participants[s] : null;
          addSlot(pred.node, ring + 1, p, slot, viaLoser: true, hidden: true);
        }
      }
    }
  }

  for (final pred in predecessors[root.eventId] ?? const <_Pred>[]) {
    expand(pred.node, 1, null);
  }

  // Angles : chaque branche se partage son secteur à parts égales entre ses entrées, de haut en bas de l'arbre.
  placeRoots(slots.where((s) => s.parent == null).toList(), -math.pi / 2, 3 * math.pi / 2);
  return RadialTree(center: root, slots: slots, rings: maxRing, ringLabels: ringLabels);
}

/// La finale du repêchage : le match du repêchage dont le gagnant va en grande finale.
String? lowerFinalId(BracketResponseDto bracket) {
  final root = bracket.nodes.firstWhereOrNull((n) => n.round == 0);
  if (root == null) return null;
  final lowerIds = bracket.nodes.where((n) => isLowerBracketName(n.name)).map((n) => n.eventId).toSet();
  return bracket.links.firstWhereOrNull((l) => l.outcome == "winner" && l.toEventId == root.eventId && lowerIds.contains(l.fromEventId))?.fromEventId;
}

/// Les deux moitiés d'un cercle de phase finale : le tableau principal en haut, le repêchage en bas
/// (à passer à [assignSectors]). `null` quand il n'y a pas de repêchage.
Map<String, (double, double)>? mainAndLowerHalves(RadialTree tree, BracketResponseDto bracket) {
  final lowerIds = bracket.nodes.where((n) => isLowerBracketName(n.name)).map((n) => n.eventId).toSet();
  if (lowerIds.isEmpty) return null;
  final heads = tree.slots.where((s) => s.parent == null).map((s) => s.matchId).toSet();
  return {for (final id in heads) id: lowerIds.contains(id) ? (0.0, math.pi) : (-math.pi, 0.0)};
}

/// Place un cercle (et ses entrées) dans le secteur d'angles [start, end] : une feuille au milieu, un cercle
/// intérieur au milieu de son secteur, que ses entrées se partagent à parts égales. Un cercle est donc toujours
/// centré sur la barre qui relie ses deux entrées, même quand une entrée a plus d'équipes derrière elle que l'autre.
/// [mirrored] inverse l'ordre des entrées, pour que la seconde moitié du cercle soit le reflet de la première.
void _place(TreeSlot slot, double start, double end, bool mirrored) {
  slot.angle = (start + end) / 2;
  if (slot.children.isEmpty) return;
  final kids = mirrored ? slot.children.reversed.toList() : slot.children;
  final width = (end - start) / kids.length;
  for (final (i, kid) in kids.indexed) {
    _place(kid, start + i * width, start + (i + 1) * width, mirrored);
  }
}

/// Les cercles de tête d'une branche (anneau 1) se partagent le secteur. [mirrorSecondHalf] : quand la branche n'a
/// qu'une tête à deux entrées (le repêchage d'une phase finale), la seconde entrée est placée en reflet de la première.
void placeRoots(List<TreeSlot> roots, double start, double end, {bool mirrorSecondHalf = false}) {
  final width = (end - start) / roots.length;
  for (final (i, root) in roots.indexed) {
    final from = start + i * width;
    final to = from + width;
    if (mirrorSecondHalf && roots.length == 1 && root.children.length == 2) {
      root.angle = (from + to) / 2;
      _place(root.children[0], from, (from + to) / 2, false);
      _place(root.children[1], (from + to) / 2, to, true);
    } else {
      _place(root, from, to, false);
    }
  }
}

/// Répartit les cercles de chaque branche sur un secteur d'angles (début, fin), au lieu de tout le cercle : une
/// poule met ses ouvertures en haut et l'élimination en bas. [sectors] est indexé par le match des cercles de
/// l'anneau 1 (la tête de la branche) ; [mirrored] liste ceux dont la seconde moitié reflète la première.
void assignSectors(RadialTree tree, Map<String, (double, double)> sectors, {Set<String> mirrored = const {}}) {
  for (final entry in sectors.entries) {
    final roots = tree.slots.where((s) => s.parent == null && s.matchId == entry.key).toList();
    final branch = <TreeSlot>[];
    void collect(TreeSlot slot) {
      branch.add(slot);
      slot.children.forEach(collect);
    }

    roots.forEach(collect);
    final rings = branch.map((s) => s.ring).fold(0, math.max);
    for (final slot in branch) {
      slot.branchRings = rings;
    }
    final (start, end) = entry.value;
    placeRoots(roots, start, end, mirrorSecondHalf: mirrored.contains(entry.key));
  }
}

// ─── Phrases par gabarit (règle 9 : jamais de texte libre) ─────────────────

/// « demain à 9 h », « aujourd'hui à 21 h 30 », « le 12 octobre à 9 h ».
String scheduleLabel(DateTime target, DateTime now) {
  const months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
  final t = target.toLocal();
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) { 0 => "aujourd'hui", 1 => "demain", _ => "le ${t.day} ${months[t.month - 1]}" };
  final minutes = t.minute == 0 ? "" : " ${t.minute.toString().padLeft(2, "0")}";
  return "$day à ${t.hour} h$minutes";
}

class TeamLine {
  const TeamLine({required this.entityId, required this.headline, this.stakes, this.matchId});
  final String entityId;
  final String headline;

  /// « Si G2 gagne… », seulement quand un match de cette équipe est à venir ou en direct.
  final String? stakes;

  /// Le match dont parle la phrase (appui → fiche du match).
  final String? matchId;
}

/// Une phrase par équipe suivie encore présente dans le tableau. Le prochain match d'une
/// équipe est le match en direct, sinon le plus proche qui la compte parmi ses
/// participants, sinon la suite de son dernier match (liens gagnant/perdant).
List<TeamLine> followedTeamLines(BracketResponseDto bracket, Set<String> followedEntityIds, DateTime now) {
  final byId = {for (final n in bracket.nodes) n.eventId: n};
  final outgoing = <String, Map<String, BracketNodeDto?>>{};
  for (final l in bracket.links) {
    outgoing.putIfAbsent(l.fromEventId, () => {})[l.outcome] = byId[l.toEventId];
  }
  DateTime? startOf(BracketNodeDto n) => n.startsAt == null ? null : DateTime.parse(n.startsAt!);
  int byStart(BracketNodeDto a, BracketNodeDto b) => (startOf(a) ?? DateTime(9999)).compareTo(startOf(b) ?? DateTime(9999));

  final lines = <TeamLine>[];
  for (final entityId in followedEntityIds) {
    final played = bracket.nodes.where((n) => n.participants.any((p) => p.entityId == entityId)).toList()..sort(byStart);
    if (played.isEmpty) continue;
    final code = teamCode(played.first.participants.firstWhere((p) => p.entityId == entityId));

    final live = played.firstWhereOrNull((n) => n.status == "live");
    final upcoming = played.where((n) => !_isFinished(n) && n.status != "live").toList();
    BracketNodeDto? next = live ?? upcoming.firstOrNull;
    if (next == null) {
      final last = played.last; // tous terminés
      final won = last.participants.any((p) => p.entityId == entityId && p.isWinner == true);
      next = outgoing[last.eventId]?[won ? "winner" : "loser"];
      if (next == null || _isFinished(next)) {
        lines.add(TeamLine(entityId: entityId, headline: won ? "$code est championne." : "$code est éliminée du tournoi.", matchId: last.eventId));
        continue;
      }
    }

    final title = stageOf(next.name).title;
    final start = startOf(next);
    final headline = next.status == "live"
        ? "$code joue en ce moment : $title."
        : start != null
            ? "$code joue ${scheduleLabel(start, now)} : $title."
            : "Prochain match de $code : $title, date à venir.";
    lines.add(TeamLine(entityId: entityId, headline: headline, stakes: _stakes(code, next, outgoing[next.eventId]), matchId: next.eventId));
  }
  return lines;
}

String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// « Si G2 gagne, elle va en demi-finale 1 ; sinon elle passe au repêchage. »
String _stakes(String code, BracketNodeDto match, Map<String, BracketNodeDto?>? out) {
  final win = out?["winner"];
  if (win == null) return "Si $code gagne, elle est championne ; sinon elle termine deuxième.";
  final onWin = "Si $code gagne, elle va en ${_lowerFirst(stageOf(win.name).title)}";
  return out?["loser"] == null ? "$onWin ; sinon elle est éliminée." : "$onWin ; sinon elle passe au repêchage.";
}

// ─── Cases d'un match ──────────────────────────────────────────────────────

/// Un côté d'un match : une équipe connue ou un libellé d'attente.
typedef MatchSide = ({String label, String? code, String? imageUrl, String? entityId, int? score, bool won, bool lost});

const _unknownSide = (label: "À déterminer", code: null, imageUrl: null, entityId: null, score: null, won: false, lost: false);

/// Les deux côtés d'un match : les participants s'ils sont connus, sinon, par lien
/// entrant, l'équipe issue d'un match déjà joué ou « Perdant du quart de finale 1 ».
List<MatchSide> matchSides(BracketNodeDto node, List<BracketLinkDto> incoming, Map<String, BracketNodeDto> byId) {
  MatchSide known(BracketParticipantDto p, {int? score}) =>
      (label: p.name, code: teamCode(p), imageUrl: p.imageUrl, entityId: p.entityId, score: score, won: p.isWinner == true, lost: p.isWinner == false);

  if (node.participants.length == 2) return [for (final p in node.participants) known(p, score: p.score?.toInt())];
  final sorted = [...incoming]..sort((a, b) => (a.slot ?? 0).compareTo(b.slot ?? 0));
  final sides = <MatchSide>[
    for (final l in sorted)
      if (byId[l.fromEventId] case final from? when from.status == "finished" && _outcomeTeam(from, l.outcome) != null)
        known(_outcomeTeam(from, l.outcome)!)
      else
        (label: placeholderLabel(l, byId), code: null, imageUrl: null, entityId: null, score: null, won: false, lost: false),
  ];
  while (sides.length < 2) {
    sides.add(_unknownSide);
  }
  return sides;
}

BracketParticipantDto? _outcomeTeam(BracketNodeDto from, String outcome) => from.participants.firstWhereOrNull((p) => p.isWinner == (outcome == "winner"));

/// Le match à mettre en avant : celui en direct, sinon le prochain d'une équipe suivie,
/// sinon le prochain à jouer. `null` quand tout est terminé.
String? nextMatchId(BracketResponseDto bracket, Set<String> followedEntityIds) {
  final live = bracket.nodes.firstWhereOrNull((n) => n.status == "live");
  if (live != null) return live.eventId;
  final upcoming = bracket.nodes.where((n) => !_isFinished(n) && n.status != "cancelled").toList()
    ..sort((a, b) => (a.startsAt ?? "9").compareTo(b.startsAt ?? "9"));
  final mine = upcoming.firstWhereOrNull((n) => n.participants.any((p) => followedEntityIds.contains(p.entityId)));
  return (mine ?? upcoming.firstOrNull)?.eventId;
}

// ─── Pyramide horizontale ──────────────────────────────────────────────────

class GridCell {
  const GridCell({required this.node, required this.col, required this.row});
  final BracketNodeDto node;
  final int col;

  /// Ligne, en cases (peut être fractionnaire : un match d'arrivée se place entre ses deux sources).
  final double row;
}

class GridLayout {
  const GridLayout({required this.cells, required this.cols, required this.rows});
  final List<GridCell> cells;
  final int cols;
  final double rows;

  GridCell? cell(String eventId) => cells.firstWhereOrNull((c) => c.node.eventId == eventId);
}

/// Place les matchs de gauche (premiers tours) à droite (décisif). Colonne = tour du **chemin des
/// gagnants** : un match qui ne reçoit que des perdants (le premier tour du repêchage, l'élimination
/// d'une poule) retombe dans la première colonne, avec les premiers matchs du tableau. Lignes : un
/// match d'arrivée se place à la moyenne de ses sources ; le repêchage forme une bande sous le
/// tableau principal.
GridLayout buildGridLayout(BracketResponseDto bracket) {
  final byId = {for (final n in bracket.nodes) n.eventId: n};
  final incoming = <String, List<BracketLinkDto>>{};
  for (final l in bracket.links) {
    if (byId.containsKey(l.fromEventId) && byId.containsKey(l.toEventId)) incoming.putIfAbsent(l.toEventId, () => []).add(l);
  }

  final cols = <String, int>{};
  int colOf(String id, Set<String> visiting) {
    final known = cols[id];
    if (known != null) return known;
    if (!visiting.add(id)) return 0; // boucle dans des données incohérentes
    var col = 0;
    for (final l in incoming[id] ?? const <BracketLinkDto>[]) {
      if (l.outcome == "winner") col = math.max(col, colOf(l.fromEventId, visiting) + 1);
    }
    visiting.remove(id);
    return cols[id] = col;
  }

  for (final n in bracket.nodes) {
    colOf(n.eventId, {});
  }

  // Dans une colonne : d'abord les matchs nourris par des gagnants (le tableau « du haut »), puis
  // ceux qui ne reçoivent que des perdants (l'élimination d'une poule), puis par horaire.
  bool loserOnly(BracketNodeDto n) => (incoming[n.eventId] ?? const <BracketLinkDto>[]).isNotEmpty && !(incoming[n.eventId]!).any((l) => l.outcome == "winner");
  bool waitsForColumn(BracketNodeDto n) =>
      (incoming[n.eventId] ?? const <BracketLinkDto>[]).any((l) => l.outcome != "winner" && cols[l.fromEventId] == cols[n.eventId]);
  int byStartThenName(BracketNodeDto a, BracketNodeDto b) {
    final byStart = (a.startsAt ?? "").compareTo(b.startsAt ?? "");
    return byStart != 0 ? byStart : a.name.compareTo(b.name);
  }

  final order = bracket.nodes.toList()
    ..sort((a, b) {
      final byCol = cols[a.eventId]!.compareTo(cols[b.eventId]!);
      if (byCol != 0) return byCol;
      if (loserOnly(a) != loserOnly(b)) return loserOnly(a) ? 1 : -1;
      // Un match qui reçoit le perdant d'un match de la même colonne (le décisif d'une poule) passe après lui.
      if (waitsForColumn(a) != waitsForColumn(b)) return waitsForColumn(a) ? 1 : -1;
      return byStartThenName(a, b);
    });

  final rows = <String, double>{};
  final nextSource = {false: 0.0, true: 0.0};
  final lastInColumn = <(bool, int), double>{};
  for (final n in order) {
    final lower = isLowerBracketName(n.name);
    final sources = (incoming[n.eventId] ?? const <BracketLinkDto>[]).where((l) => isLowerBracketName(byId[l.fromEventId]!.name) == lower && rows.containsKey(l.fromEventId)).toList();
    var row = sources.isEmpty ? nextSource[lower]! : sources.map((l) => rows[l.fromEventId]!).reduce((a, b) => a + b) / sources.length;
    if (sources.isEmpty) nextSource[lower] = row + 1;
    final key = (lower, cols[n.eventId]!);
    final last = lastInColumn[key];
    if (last != null && row < last + 1) row = last + 1;
    lastInColumn[key] = row;
    rows[n.eventId] = row;
  }

  final lowerIds = bracket.nodes.where((n) => isLowerBracketName(n.name)).map((n) => n.eventId).toSet();
  final mainMax = bracket.nodes.where((n) => !lowerIds.contains(n.eventId)).map((n) => rows[n.eventId]!).fold(0.0, math.max);
  final offset = lowerIds.isEmpty ? 0.0 : mainMax + 1.4;
  for (final id in lowerIds) {
    rows[id] = rows[id]! + offset;
  }
  // Le match décisif nourri par les deux tableaux se place entre les deux.
  for (final n in order) {
    final links = incoming[n.eventId] ?? const <BracketLinkDto>[];
    if (!lowerIds.contains(n.eventId) && links.any((l) => lowerIds.contains(l.fromEventId))) {
      rows[n.eventId] = links.map((l) => rows[l.fromEventId]!).reduce((a, b) => a + b) / links.length;
    }
  }

  return GridLayout(
    cells: [for (final n in bracket.nodes) GridCell(node: n, col: cols[n.eventId]!, row: rows[n.eventId]!)],
    cols: cols.values.fold(0, math.max) + 1,
    rows: rows.values.fold(0.0, math.max) + 1,
  );
}

// ─── Ordre des poules et onglet par défaut ─────────────────────────────────

/// Les poules dans l'ordre reçu (alphabétique), celles qui ont un match en direct d'abord.
List<String> liveGroupsFirst(List<String> groupIds, Set<String> liveGroupIds) => [
      ...groupIds.where(liveGroupIds.contains),
      ...groupIds.where((id) => !liveGroupIds.contains(id)),
    ];

/// L'onglet à ouvrir : « Phase finale » (1) dès que les poules sont toutes terminées ou que la phase
/// finale a commencé, « Groupes » (0) avant. Sert tant que la personne n'a pas choisi elle-même un
/// onglet : l'écran suit ainsi le tournoi sans qu'on ait à le faire.
int defaultBracketTab({required List<BracketResponseDto?> groups, BracketResponseDto? playoffs}) {
  if (playoffs == null) return 0;
  // Pas de poules (une phase finale seule) : rien à montrer dans « Groupes », on ouvre directement la phase finale.
  if (groups.isEmpty) return 1;
  final playoffsStarted = playoffs.nodes.any((n) => n.status != "scheduled");
  final groupsDone = groups.every((g) => g != null && g.nodes.isNotEmpty && g.nodes.every(_isFinished));
  return playoffsStarted || groupsDone ? 1 : 0;
}
