// Structures (docs/04 J23, #A4) : « G2 Esports » en Valorant et « G2 Esports » en League of Legends sont deux
// entités (une par jeu chez PandaScore) mais une seule structure. Le rapprochement est automatique, par le nom :
// deux équipes de même clé appartiennent à la même structure. Règle pure, sans accès base.

// Mots qui varient d'un jeu à l'autre pour la même structure (« Team Liquid », « Liquid », « Fnatic Esports »).
const NOISE_WORDS = /\b(esports?|e-sports?|gaming|team|club)\b/g;

/**
 * Clé de rapprochement d'une équipe : minuscules, sans accents, sans « Team »/« Esports », sans ponctuation.
 * « Gen.G Esports » → « geng » ; « Team Liquid » → « liquid » ; `null` si le nom est trop court pour être sûr.
 */
export function organizationKey(teamName: string): string | null {
  const key = teamName
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(NOISE_WORDS, " ")
    .replace(/[^a-z0-9]/g, "");
  return key.length >= 2 ? key : null;
}
