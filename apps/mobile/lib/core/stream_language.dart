import "dart:ui" show PlatformDispatcher;
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Les langues des chaînes de diffusion de Riot (J21), avec leur nom dans la langue elle-même.
const streamLanguages = [
  (code: "fr", label: "Français"),
  (code: "en", label: "English"),
  (code: "es", label: "Español"),
  (code: "pt", label: "Português"),
  (code: "tr", label: "Türkçe"),
  (code: "ja", label: "日本語"),
  (code: "ko", label: "한국어"),
  (code: "zh", label: "中文"),
  (code: "th", label: "ไทย"),
  (code: "id", label: "Bahasa Indonesia"),
];

/// La langue du téléphone si on a une chaîne dans cette langue, sinon l'anglais.
String deviceStreamLanguage() {
  final code = PlatformDispatcher.instance.locale.languageCode;
  return streamLanguages.any((l) => l.code == code) ? code : "en";
}

/// La langue des streams, retenue sur le téléphone : un invité n'a pas de compte où la ranger.
/// Elle part de la langue du téléphone ; l'onboarding et les Réglages permettent de la changer.
class StreamLanguageNotifier extends Notifier<String> {
  static const _key = "streams.language";

  @override
  String build() {
    _load();
    return deviceStreamLanguage();
  }

  // Sans plugin (tests), on garde la langue du téléphone : un échec de lecture ne doit rien casser.
  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved != null) state = saved;
    } catch (_) {}
  }

  void select(String code) {
    state = code;
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, code)).catchError((_) => false);
  }
}

final streamLanguageProvider = NotifierProvider<StreamLanguageNotifier, String>(StreamLanguageNotifier.new);

/// Les chaînes de la langue choisie d'abord, les autres ensuite ; à égalité, l'ordre de l'API (la principale en tête).
List<StreamDto> sortStreamsFor(Iterable<StreamDto> streams, String language) {
  final list = streams.toList();
  return [for (final s in list.where((s) => s.language == language)) s, for (final s in list.where((s) => s.language != language)) s];
}
