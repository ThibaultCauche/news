import "package:news_api_client/news_api_client.dart";

/// Formule 1 (J28) : tout ce qui se calcule sans écran. Jolpica donne les noms en anglais (« Australian Grand
/// Prix ») ; l'appli les montre en français, et garde le nom d'origine quand elle ne le connaît pas.
const _grandPrixPlaces = {
  "Australian": "d'Australie",
  "Chinese": "de Chine",
  "Japanese": "du Japon",
  "Bahrain": "de Bahreïn",
  "Saudi Arabian": "d'Arabie saoudite",
  "Miami": "de Miami",
  "Emilia Romagna": "d'Émilie-Romagne",
  "Monaco": "de Monaco",
  "Canadian": "du Canada",
  "Barcelona": "de Barcelone",
  "Spanish": "d'Espagne",
  "Austrian": "d'Autriche",
  "British": "de Grande-Bretagne",
  "Hungarian": "de Hongrie",
  "Belgian": "de Belgique",
  "Dutch": "des Pays-Bas",
  "Italian": "d'Italie",
  "Azerbaijan": "d'Azerbaïdjan",
  "Singapore": "de Singapour",
  "United States": "des États-Unis",
  "Mexico City": "de Mexico",
  "Mexican": "du Mexique",
  "Brazilian": "du Brésil",
  "São Paulo": "de São Paulo",
  "Las Vegas": "de Las Vegas",
  "Qatar": "du Qatar",
  "Abu Dhabi": "d'Abou Dhabi",
};

String grandPrixName(String name) {
  final match = RegExp(r"^(.+) Grand Prix$").firstMatch(name);
  final place = match == null ? null : _grandPrixPlaces[match.group(1)];
  return place == null ? name : "Grand Prix $place";
}

/// « RUS · ANT · LEC » : les trois premiers d'une session, dans l'ordre. Vide tant qu'il n'y a pas de classement.
String podiumLabel(List<EventParticipantDto> participants) {
  final podium = [...participants]..sort((a, b) => (a.score ?? 99).compareTo(b.score ?? 99));
  return podium.take(3).map((p) => p.shortName ?? p.name).join(" · ");
}

/// Position à l'arrivée : le chiffre, ou « Ab. » (abandon), « Disq. », « Forf. » quand le pilote n'est pas classé.
String positionLabel(ClassificationRowDto row) => switch (row.positionText) {
  "R" => "Ab.",
  "D" => "Disq.",
  "W" => "Forf.",
  "E" => "Excl.",
  "N" => "NC",
  final text => text,
};

/// Écart ou temps d'un pilote : « 1:23:06.801 » pour le vainqueur, « +2.974 » pour les suivants, « +1 tour » pour un
/// pilote doublé, la cause d'un abandon sinon (traduite quand elle est courante). Jolpica donne aux pilotes doublés
/// l'écart avec la première voiture de **leur** tour : le temps serait trompeur, on compte donc les tours de retard
/// sur le vainqueur (`winnerLaps`).
String gapLabel(ClassificationRowDto row, {num? winnerLaps}) {
  final status = row.status ?? "";
  if (row.positionText == "R" && (status == "Lapped" || status == "Retired" || status.isEmpty)) return "Abandon";
  final laps = row.laps;
  final behind = winnerLaps != null && laps != null ? (winnerLaps - laps).toInt() : 0;
  if (behind > 0 && (status == "Lapped" || status.startsWith("+"))) return "+$behind tour${behind > 1 ? "s" : ""}";
  final time = row.time;
  if (time != null && time.isNotEmpty) return time;
  final lapped = RegExp(r"^\+(\d+) Laps?$").firstMatch(status);
  if (lapped != null) {
    final n = int.parse(lapped.group(1)!);
    return "+$n tour${n > 1 ? "s" : ""}";
  }
  return switch (status) {
    "" || "Finished" => "",
    "Retired" => "Abandon",
    "Disqualified" => "Disqualifié",
    "Did not start" => "Non partant",
    "Accident" || "Collision" || "Spun off" => "Accident",
    "Engine" || "Power Unit" => "Moteur",
    "Gearbox" || "Transmission" || "Clutch" => "Transmission",
    "Brakes" || "Suspension" || "Hydraulics" || "Electrical" || "Overheating" || "Water leak" || "Oil leak" || "Fuel system" => "Panne",
    final other => other,
  };
}

/// Meilleur temps d'une ligne de qualifications : le dernier tour de qualification que le pilote a pu faire (Q3, puis Q2, puis Q1).
String? qualifyingTime(ClassificationRowDto row) => row.q3 ?? row.q2 ?? row.q1;

/// Séance où l'on classe des pilotes par temps au tour (qualifications) plutôt que par écart d'arrivée.
bool isQualifying(String sessionName) => sessionName.toLowerCase().startsWith("qualifications");

/// Une session a-t-elle un classement à montrer (course, sprint, qualifications) ? Les essais libres n'en ont pas.
bool hasClassification(String sessionName) => !sessionName.toLowerCase().startsWith("essais");
