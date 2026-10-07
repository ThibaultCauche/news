// Diffusions d'un match (J21, lot 6) : seulement les chaînes de l'éditeur du jeu (Riot pour
// Valorant), une par langue. Les co-streamers ne sont pas gérés : un bouton « Autres streamers »
// mène à la page du jeu chez Twitch.

export interface StreamDTO {
  /** Pseudo de la chaîne Twitch, tel qu'il apparaît dans l'URL ; `null` pour une autre plateforme. */
  channel: string | null;
  url: string;
  language: string | null;
  official: boolean;
}

/** Page du jeu sur Twitch, où l'on trouve tous les streamers (« Autres streamers »). */
const TWITCH_DIRECTORY: Record<string, string> = {
  valorant: "https://www.twitch.tv/directory/category/valorant",
  "league-of-legends": "https://www.twitch.tv/directory/category/league-of-legends",
  "super-smash-bros-ultimate": "https://www.twitch.tv/directory/category/super-smash-bros-ultimate",
};

export function moreStreamersUrl(game: string | null | undefined): string | null {
  return (game && TWITCH_DIRECTORY[game]) || null;
}

/** `https://www.twitch.tv/Valorant_FR` → `valorant_fr` ; `null` hors Twitch. */
export function twitchChannelOf(url: string): string | null {
  const m = /^https?:\/\/(?:www\.)?twitch\.tv\/([A-Za-z0-9_]+)\/?$/.exec(url.trim());
  return m ? m[1].toLowerCase() : null;
}

// PandaScore ne marque « officielles » que les chaînes principales (`valorant`, `valorant_emea`) ;
// les chaînes de langue de Riot (`valorant_fr`, `valorant_jpn`…) arrivent avec `official: false`, au
// milieu des co-streamers. Leur nom les trahit.
const RIOT_CHANNEL = /^(valorant(esports)?|lolesports|riotgames)(_|$)/;

/** Ne garde que les chaînes de l'éditeur, une seule fois chacune (l'officielle l'emporte sur le doublon). */
export function pickPublisherStreams(raw: { raw_url?: string | null; language?: string | null; official?: boolean; main?: boolean }[] | null | undefined): StreamDTO[] {
  const byChannel = new Map<string, StreamDTO & { main: boolean }>();
  for (const s of raw ?? []) {
    if (!s.raw_url) continue;
    const channel = twitchChannelOf(s.raw_url);
    if (!channel) continue; // YouTube, Douyu… : pas de logo ni de « en direct », hors périmètre
    if (!s.official && !RIOT_CHANNEL.test(channel)) continue;
    const next = { channel, url: `https://www.twitch.tv/${channel}`, language: s.language ?? null, official: Boolean(s.official), main: Boolean(s.main) };
    const prev = byChannel.get(channel);
    if (!prev || (next.official && !prev.official)) byChannel.set(channel, next);
  }
  // Le flux principal d'abord, puis par langue : un ordre stable (l'appli remonte celui de l'utilisateur).
  return [...byChannel.values()]
    .sort((a, b) => Number(b.main) - Number(a.main) || (a.language ?? "").localeCompare(b.language ?? "") || a.channel!.localeCompare(b.channel!))
    .map(({ main: _main, ...stream }) => stream);
}
