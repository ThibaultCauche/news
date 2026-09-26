import { buildCompetitionIntro, parseInfoboxFields } from "./format";

// Vraie réponse `action=parse&page=VCT/2026/Champions&prop=wikitext&section=0`
// (docs/04 CLAUDE.md : réutiliser de vraies réponses comme fixtures), récupérée le
// 2026-09-26 avec un User-Agent conforme (docs/01).
const CHAMPIONS_2026_INFOBOX_WIKITEXT = `{{DISPLAYTITLE:VALORANT Champions 2026}}
{{VCT Champions Navbox}}
{{Infobox league
|liquipediatier=S-Tier
|publishertier=highlighted
|name=VALORANT Champions 2026
|shortname=VCT Champions 2026
|tickername=Champions 2026
|organizer=Riot Games
|organizer-link=https://playvalorant.com/
|organizer2=TJ Sports
|prizepoolusd=2,250,000
|type=Offline
|country=China
|city=Shanghai
|venue1=Mercedes-Benz Arena|venue1link=https://www.mercedes-benzarena.com/en|venue1desc=Top 4
|format=
|patch=13.05
|sdate=2026-09-24
|edate=2026-10-18
|web=https://valorantesports.com
|team_number=16
|previous=VCT/2025/Champions{{!}}Champions 2025
|next=VCT/2027/Champions{{!}}Champions 2027
|next2=
}}`;

describe("parseInfoboxFields + buildCompetitionIntro (VCT/2026/Champions, vraie réponse Liquipedia)", () => {
  it("lit les champs structurés de l'infobox", () => {
    const fields = parseInfoboxFields(CHAMPIONS_2026_INFOBOX_WIKITEXT);
    expect(fields.organizer).toBe("Riot Games");
    expect(fields.city).toBe("Shanghai");
    expect(fields.country).toBe("China");
    expect(fields.sdate).toBe("2026-09-24");
    expect(fields.edate).toBe("2026-10-18");
    expect(fields.team_number).toBe("16");
    expect(fields.prizepoolusd).toBe("2,250,000");
  });

  it("construit une phrase de contexte en français, sans reprendre le texte libre anglais", () => {
    const fields = parseInfoboxFields(CHAMPIONS_2026_INFOBOX_WIKITEXT);
    expect(buildCompetitionIntro(fields)).toBe(
      "Compétition organisée par Riot Games, à Shanghai. Du 24 septembre 2026 au 18 octobre 2026. 16 équipes, 2,250,000 $ de dotation.",
    );
  });

  it("renvoie `null` si les champs connus manquent tous", () => {
    expect(buildCompetitionIntro({})).toBeNull();
  });
});
