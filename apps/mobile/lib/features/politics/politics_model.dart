import "dart:math" as math;
import "dart:ui" show Offset;

import "package:news_api_client/news_api_client.dart";

/// Politique (J29) : règles d'affichage pures, testables sans écran.

/// Ce qu'un siège de l'hémicycle a voté. Quatre cas, distingués par la forme autant que par la couleur
/// (règle 12 : jamais la couleur seule).
enum SeatKind { pour, contre, abstention, absent }

/// Slug du « jeu » de la politique côté API (`competition.game`) : la page jeu s'ouvre sur la page Politique.
const politicsGame = "assemblee-nationale";

/// Format des compétitions qui sont une loi (`competition.format`).
const lawFormat = "law_process";

/// Slug du « jeu » des élections (J29c) : même page Politique.
const electionsGame = "elections";

bool isPolitics(String? game) => game == politicsGame || game == electionsGame;

/// Les sièges d'un vote, groupe après groupe (dans l'ordre de l'API, alphabétique) : pour, contre, abstention, puis
/// les absents. Un groupe qui compte plus de membres que de voix exprimées complète avec des absents.
List<SeatKind> seatKinds(Iterable<VoteGroupDto> groups) {
  final seats = <SeatKind>[];
  for (final g in groups) {
    final pour = g.pour.toInt(), contre = g.contre.toInt(), abst = g.abst.toInt();
    final voted = pour + contre + abst + g.nonVotants.toInt();
    seats
      ..addAll(List.filled(pour, SeatKind.pour))
      ..addAll(List.filled(contre, SeatKind.contre))
      ..addAll(List.filled(abst, SeatKind.abstention))
      ..addAll(List.filled(math.max(g.members.toInt(), voted) - pour - contre - abst, SeatKind.absent));
  }
  return seats;
}

// Rayon de chaque rangée et nombre de sièges qu'elle porte (proportionnel à son rayon).
(List<double>, List<int>) _layout(int total) {
  final rows = hemicycleRows(total);
  const inner = 0.4;
  final radii = [for (var k = 0; k < rows; k++) inner + (1 - inner) * (rows == 1 ? 1 : k / (rows - 1))];
  final sum = radii.fold<double>(0, (a, b) => a + b);
  final counts = [for (final r in radii) (total * r / sum).round()];
  counts[rows - 1] += total - counts.fold<int>(0, (a, b) => a + b);
  return (radii, counts);
}

/// Rangées de l'hémicycle pour [total] sièges : environ 10 pour les 577 députés.
int hemicycleRows(int total) => math.max(3, (math.sqrt(total) / 2.4).round());

/// Position de chaque siège dans un demi-cercle de rayon 1 (x de -1 à 1, y de 0 à 1, vers le haut), de la gauche à la
/// droite. Les sièges sont répartis sur [hemicycleRows] arcs concentriques puis triés par angle : donner les sièges
/// dans l'ordre des groupes les range donc en parts de tarte, comme dans l'hémicycle réel.
List<Offset> hemicycleSeats(int total) {
  if (total <= 0) return const [];
  final (radii, counts) = _layout(total);
  final rows = radii.length;
  final seats = <({double angle, double radius})>[];
  for (var k = 0; k < rows; k++) {
    final n = counts[k];
    for (var j = 0; j < n; j++) {
      seats.add((angle: n == 1 ? math.pi / 2 : math.pi * (1 - j / (n - 1)), radius: radii[k]));
    }
  }
  seats.sort((a, b) {
    final byAngle = b.angle.compareTo(a.angle);
    return byAngle != 0 ? byAngle : a.radius.compareTo(b.radius);
  });
  return [for (final s in seats) Offset(s.radius * math.cos(s.angle), s.radius * math.sin(s.angle))];
}

/// Rayon d'un point, en fraction du rayon de l'hémicycle : le plus petit des deux espaces libres (entre deux rangées, et
/// entre deux sièges d'une même rangée, la plus serrée étant la rangée intérieure), pour que les points ne se touchent
/// jamais. Vérifié sur un téléphone : avec 163 sièges sur 5 rangées, le seul écart entre rangées les faisait fusionner.
double hemicycleDotFraction(int total) {
  if (total <= 0) return 0;
  final (radii, counts) = _layout(total);
  var gap = radii.length <= 1 ? 0.3 : 0.6 / (radii.length - 1);
  for (var k = 0; k < radii.length; k++) {
    if (counts[k] > 1) gap = math.min(gap, math.pi * radii[k] / (counts[k] - 1));
  }
  return gap * 0.4;
}

const _months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];

/// « 12 mai » dans l'année en cours, « 12 mai 2025 » sinon. Vide si la date manque ou est illisible.
String lawDayLabel(String? iso, {DateTime? now}) {
  final date = iso == null || iso.length < 10 ? null : DateTime.tryParse(iso.substring(0, 10));
  if (date == null) return "";
  final base = "${date.day == 1 ? "1er" : date.day} ${_months[date.month - 1]}";
  return date.year == (now ?? DateTime.now()).year ? base : "$base ${date.year}";
}

/// Libellé de la position d'un groupe (« Pour », « Contre », « Abstention », « Pas de vote »).
String positionLabel(String position) => switch (position) {
  "pour" => "Pour",
  "contre" => "Contre",
  "abstention" => "Abstention",
  _ => "Pas de vote",
};

/// Qui a déposé le texte : « Le gouvernement », « Ayda Hadizadeh, Socialistes et apparentés », « Des sénateurs ».
String authorLabel(LawAuthorDto author) {
  switch (author.kind) {
    case LawAuthorDtoKindEnum.government:
      return "Le gouvernement";
    case LawAuthorDtoKindEnum.senators:
      return "Des sénateurs";
    default:
      final name = author.name;
      if (name == null) return "Des députés";
      return author.group == null ? name : "$name, ${author.group}";
  }
}

/// « et 3 cosignataires » (rien sans cosignataire).
String cosignersLabel(int count) => count <= 0 ? "" : count == 1 ? "1 cosignataire" : "$count cosignataires";

const _weekdays = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"];

/// « dimanche 18 avril 2027 » à partir d'un jour « AAAA-MM-JJ ».
String electionDateLabel(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : "${_weekdays[d.weekday - 1]} ${d.day == 1 ? "1er" : d.day} ${_months[d.month - 1]} ${d.year}";
}

/// Combien de temps avant l'heure où les résultats deviennent publics : « dans 3 h 12 », « dans 12 min », « dans 5 jours ».
/// Vide une fois l'heure passée.
String liftsInLabel(String liftsAtIso, {DateTime? now}) {
  final lifts = DateTime.tryParse(liftsAtIso);
  if (lifts == null) return "";
  final left = lifts.difference(now ?? DateTime.now());
  if (left.isNegative || left == Duration.zero) return "";
  if (left.inDays >= 2) return "dans ${left.inDays} jours";
  if (left.inHours >= 1) {
    final minutes = left.inMinutes % 60;
    return "dans ${left.inHours} h${minutes == 0 ? "" : " ${minutes.toString().padLeft(2, "0")}"}";
  }
  return "dans ${math.max(1, left.inMinutes)} min";
}

/// « 1ᵉʳ tour » / « 2ᵈ tour ».
String roundLabel(num round) => round.toInt() == 1 ? "1ᵉʳ tour" : "2ᵈ tour";

/// « 50,4 % » : un pourcentage à la française, une décimale.
String frPercent(num value) => "${value.toStringAsFixed(1).replaceAll(".", ",")} %";

/// 12 345 → « 12 345 » (espace insécable fine entre les milliers).
String frInt(num value) {
  final digits = value.toInt().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write("\u202f");
    out.write(digits[i]);
  }
  return out.toString();
}
