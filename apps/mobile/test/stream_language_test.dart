import "package:flutter_test/flutter_test.dart";
import "package:mobile/core/stream_language.dart";
import "package:news_api_client/news_api_client.dart";

StreamDto _s(String channel, String lang) => StreamDto((b) => b
  ..channel = channel
  ..url = "https://www.twitch.tv/$channel"
  ..language = lang);

void main() {
  test("la langue choisie passe en premier, le reste garde l'ordre de l'API", () {
    final sorted = sortStreamsFor([_s("valorant", "en"), _s("valorant_es", "es"), _s("valorant_fr", "fr"), _s("valorant_br", "pt")], "fr");
    expect(sorted.map((s) => s.channel), ["valorant_fr", "valorant", "valorant_es", "valorant_br"]);
  });

  test("sans chaîne dans la langue : rien ne change", () {
    final sorted = sortStreamsFor([_s("valorant", "en"), _s("valorant_fr", "fr")], "ja");
    expect(sorted.map((s) => s.channel), ["valorant", "valorant_fr"]);
  });
}
