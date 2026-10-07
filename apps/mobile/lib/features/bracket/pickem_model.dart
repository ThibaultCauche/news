/// Un match du pick'em, réduit à ce qu'il faut pour déduire les équipes possibles (miroir de
/// `pickemCandidates` dans `packages/domain/src/pickem.ts` : le serveur revérifie à l'enregistrement).
typedef PickemNode = ({String id, List<String> participants, List<({String fromId, bool winner})> feeders});

/// Équipes qu'on peut choisir pour chaque match, d'après ses propres choix des tours précédents.
Map<String, List<String>> pickemCandidates(List<PickemNode> nodes, Map<String, String> picks) {
  final byId = {for (final n in nodes) n.id: n};
  final memo = <String, List<String>>{};
  final visiting = <String>{};
  List<String> resolve(String id) {
    final known = memo[id];
    if (known != null) return known;
    final node = byId[id];
    if (node == null || !visiting.add(id)) return const [];
    final out = [...node.participants];
    // Deux équipes réelles connues : ce sont elles, quoi qu'on ait choisi plus haut.
    if (out.length >= 2) {
      visiting.remove(id);
      return memo[id] = out;
    }
    for (final f in node.feeders) {
      final from = resolve(f.fromId);
      final winner = picks[f.fromId];
      if (winner == null || !from.contains(winner)) continue;
      final team = f.winner ? winner : from.where((t) => t != winner).firstOrNull;
      if (team != null && !out.contains(team)) out.add(team);
    }
    visiting.remove(id);
    return memo[id] = out;
  }

  for (final n in nodes) {
    resolve(n.id);
  }
  return memo;
}

/// Retire les choix qui ne tiennent plus (l'équipe ne peut plus jouer ce match après un changement plus haut).
/// Répété jusqu'à stabilité : retirer un choix peut en invalider un autre.
Map<String, String> prunePickem(List<PickemNode> nodes, Map<String, String> picks) {
  var current = {...picks};
  while (true) {
    final candidates = pickemCandidates(nodes, current);
    final next = {for (final e in current.entries) if (candidates[e.key]?.contains(e.value) ?? false) e.key: e.value};
    if (next.length == current.length) return next;
    current = next;
  }
}

/// Choisir un champion en un tap (J25) : l'équipe gagne tous ses matchs jusqu'à la finale, en suivant les liens
/// « vainqueur ». Renvoie ces choix ; l'appelant les mêle au reste du tableau puis retire ce qui ne tient plus.
Map<String, String> championPath(List<PickemNode> nodes, String teamId) {
  final next = <String, String>{};
  for (final n in nodes) {
    for (final f in n.feeders) {
      if (f.winner) next[f.fromId] = n.id;
    }
  }
  final byId = {for (final n in nodes) n.id: n};
  final start = nodes.where((n) => n.participants.contains(teamId)).firstOrNull;
  final path = <String, String>{};
  var at = start?.id;
  while (at != null && byId.containsKey(at) && !path.containsKey(at)) {
    path[at] = teamId;
    at = next[at];
  }
  return path;
}

/// Tour de chaque match : la longueur de la plus longue chaîne de prédécesseurs (premier tour = 0). Sert à ranger les
/// matchs en colonnes.
Map<String, int> pickemRounds(List<PickemNode> nodes) {
  final byId = {for (final n in nodes) n.id: n};
  final memo = <String, int>{};
  int depth(String id, Set<String> seen) {
    final known = memo[id];
    if (known != null) return known;
    final node = byId[id];
    if (node == null || !seen.add(id)) return 0;
    var best = 0;
    for (final f in node.feeders) {
      final d = depth(f.fromId, seen) + 1;
      if (d > best) best = d;
    }
    seen.remove(id);
    return memo[id] = best;
  }

  return {for (final n in nodes) n.id: depth(n.id, <String>{})};
}
