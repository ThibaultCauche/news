const _accents = {
  "àáâãäå": "a",
  "çć": "c",
  "èéêë": "e",
  "ìíîï": "i",
  "ñ": "n",
  "òóôõöø": "o",
  "ùúûü": "u",
  "ýÿ": "y",
  "œ": "oe",
  "æ": "ae",
};

/// Minuscules et sans accents, pour comparer une recherche à un nom
/// ("Épées" trouve "epees") sans dépendance externe.
String normalizeSearch(String input) {
  final lower = input.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    var replaced = ch;
    for (final entry in _accents.entries) {
      if (entry.key.contains(ch)) {
        replaced = entry.value;
        break;
      }
    }
    out.write(replaced);
  }
  return out.toString();
}
