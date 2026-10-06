import { moreStreamersUrl, pickPublisherStreams, twitchChannelOf } from "./streams";

const s = (raw_url: string, language: string, official = false, main = false) => ({ raw_url, language, official, main });

describe("pickPublisherStreams", () => {
  it("garde les chaînes de l'éditeur, officielles ou non, et écarte co-streamers et autres plateformes", () => {
    const streams = pickPublisherStreams([
      s("https://www.twitch.tv/valorant_fr", "fr"),
      s("https://www.twitch.tv/harmii", "de"),
      s("https://www.youtube.com/watch?v=abc", "fr"),
      s("https://www.twitch.tv/VALORANT", "en", true, true),
      s("https://www.twitch.tv/valorantesports_cn", "zh"),
    ]);
    expect(streams.map((x) => x.channel)).toEqual(["valorant", "valorant_fr", "valorantesports_cn"]);
  });

  it("une chaîne en double n'apparaît qu'une fois, la version officielle l'emporte", () => {
    const streams = pickPublisherStreams([s("https://www.twitch.tv/valorant_fr", "fr"), s("https://www.twitch.tv/VALORANT_fr", "fr", true)]);
    expect(streams).toEqual([{ channel: "valorant_fr", url: "https://www.twitch.tv/valorant_fr", language: "fr", official: true }]);
  });

  it("une chaîne officielle à nom libre (événement) est gardée", () => {
    expect(pickPublisherStreams([s("https://www.twitch.tv/ewc_stcarena_en", "en", true, true)]).map((x) => x.channel)).toEqual(["ewc_stcarena_en"]);
  });

  it("sans flux : liste vide", () => {
    expect(pickPublisherStreams(undefined)).toEqual([]);
  });
});

describe("twitchChannelOf / moreStreamersUrl", () => {
  it("lit le pseudo en minuscules, rien hors Twitch", () => {
    expect(twitchChannelOf("https://www.twitch.tv/Valorant_FR")).toBe("valorant_fr");
    expect(twitchChannelOf("https://www.youtube.com/watch?v=x")).toBeNull();
  });
  it("la page du jeu n'existe que pour les jeux connus", () => {
    expect(moreStreamersUrl("valorant")).toContain("twitch.tv/directory");
    expect(moreStreamersUrl("lol")).toBeNull();
  });
});
