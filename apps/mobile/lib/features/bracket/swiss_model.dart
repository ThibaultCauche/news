import "package:news_api_client/news_api_client.dart";

/// Logique pure de la phase suisse (J23, aucun widget) : rondes, groupes par bilan, qualifiées et éliminées.
/// Tout est dérivé de `BracketResponseDto` ; l'API ne renvoie pas de classement suisse à part.

/// 3 victoires qualifient, 3 défaites éliminent (mêmes seuils que `packages/domain`, `SWISS_WINS_TO_QUALIFY`).
const swissWinsToQualify = 3;
const swissLossesToEliminate = 3;

/// Les matchs d'une ronde qui opposent des équipes au même bilan (« 2-1 »).
class SwissGroup {
  const SwissGroup({required this.record, required this.matches});

  /// « 0-0 », « 2-1 »… : le bilan des équipes **avant** ces matchs. « ? » tant que les équipes sont inconnues.
  final String record;
  final List<BracketNodeDto> matches;
}

class SwissRound {
  const SwissRound({required this.number, required this.groups});

  final int number;
  final List<SwissGroup> groups;
}

class SwissLayout {
  const SwissLayout({required this.rounds, required this.qualified, required this.eliminated});

  final List<SwissRound> rounds;
  final List<BracketParticipantDto> qualified;
  final List<BracketParticipantDto> eliminated;
}

final _roundName = RegExp(r"^\s*round\s+(\d+)", caseSensitive: false);

/// Numéro de ronde lu dans le nom du match (« Round 3: G2 vs T1 »), `null` si le nom n'en a pas.
int? swissRoundOf(String matchName) {
  final m = _roundName.firstMatch(matchName);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Range les matchs en rondes puis en groupes de même bilan. Le bilan d'une équipe est celui qu'elle avait avant
/// la ronde : on avance ronde par ronde, en comptant les victoires et défaites des matchs terminés.
SwissLayout buildSwissLayout(BracketResponseDto bracket) {
  final byRound = <int, List<BracketNodeDto>>{};
  for (final node in bracket.nodes) {
    final round = swissRoundOf(node.name);
    if (round != null) byRound.putIfAbsent(round, () => []).add(node);
  }
  final records = <String, ({int wins, int losses})>{};
  final teams = <String, BracketParticipantDto>{};
  final rounds = <SwissRound>[];

  for (final number in (byRound.keys.toList()..sort())) {
    final matches = byRound[number]!..sort((a, b) => (a.startsAt ?? "").compareTo(b.startsAt ?? ""));
    final groups = <String, List<BracketNodeDto>>{};
    for (final match in matches) {
      final first = match.participants.isEmpty ? null : match.participants.first;
      final record = first == null ? null : (records[first.entityId] ?? (wins: 0, losses: 0));
      groups.putIfAbsent(record == null ? "?" : "${record.wins}-${record.losses}", () => []).add(match);
    }
    rounds.add(SwissRound(number: number, groups: [for (final e in _sortedRecords(groups.keys)) SwissGroup(record: e, matches: groups[e]!)]));

    // Les résultats de la ronde ne comptent qu'une fois la ronde parcourue : ses matchs se jouent à bilan égal.
    for (final match in matches) {
      for (final p in match.participants) {
        teams[p.entityId] = p;
        final r = records[p.entityId] ?? (wins: 0, losses: 0);
        if (match.status == "finished" && p.isWinner == true) records[p.entityId] = (wins: r.wins + 1, losses: r.losses);
        if (match.status == "finished" && p.isWinner == false) records[p.entityId] = (wins: r.wins, losses: r.losses + 1);
      }
    }
  }

  List<BracketParticipantDto> where(bool Function(({int wins, int losses}) r) test) =>
      [for (final e in records.entries) if (test(e.value)) teams[e.key]!]..sort((a, b) => a.name.compareTo(b.name));
  return SwissLayout(
    rounds: rounds,
    qualified: where((r) => r.wins >= swissWinsToQualify),
    eliminated: where((r) => r.losses >= swissLossesToEliminate),
  );
}

// Les bilans les plus forts d'abord (« 2-0 » avant « 1-1 » avant « 0-2 »), « ? » à la fin.
Iterable<String> _sortedRecords(Iterable<String> records) {
  int score(String r) {
    if (r == "?") return -100;
    final parts = r.split("-").map(int.parse).toList();
    return parts[0] * 10 - parts[1];
  }

  return records.toList()..sort((a, b) => score(b).compareTo(score(a)));
}
