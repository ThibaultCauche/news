import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { organizationKey } from "@news/domain";

// Glossaire (docs/03 §7, écran 04) : textes écrits une fois, pas générés — c'est la
// seule utilisation manuelle de `context_snippet`, le reste (pourquoi ce match
// compte) est calculé par des règles (`packages/domain/context.ts`). Idempotent
// (upsert par clé naturelle `target_type`/`target_id`/`kind`, règle 4 de CLAUDE.md) :
// on peut rejouer ce script sans dupliquer ni écraser une modification manuelle plus
// récente en base — sauf qu'ici, le seed EST la source de vérité du texte.
const GLOSSARY_TERMS: { term: string; text: string }[] = [
  {
    term: "BO1",
    text: "« Best of 1 » : un seul match décide, pas de deuxième chance. Utilisé tôt dans un tournoi ou en phase de groupes, quand il y a beaucoup de matchs à jouer.",
  },
  {
    term: "BO3",
    text: "« Best of 3 » : la première équipe qui gagne 2 cartes remporte le match. Si une équipe gagne les deux premières, la 3e ne se joue pas. Un match dure en général 1 h 30 à 2 h 30.",
  },
  {
    term: "BO5",
    text: "« Best of 5 » : la première équipe qui gagne 3 cartes remporte le match. Réservé aux matchs les plus importants (grande finale, finale d'un tableau). Un match peut durer plus de 3 h.",
  },
  {
    term: "tableau principal",
    text: "La partie du bracket où une seule défaite n'élimine pas encore une équipe (sauf en simple élimination) : y rester le plus longtemps possible garantit le meilleur classement.",
  },
  {
    term: "repêchage",
    text: "Le « lower bracket » : les équipes qui perdent dans le tableau principal y ont une deuxième chance. Y perdre une nouvelle fois élimine définitivement l'équipe du tournoi.",
  },
  {
    term: "triple élimination",
    text: "Format du Kickoff : chaque équipe a 3 vies (3 défaites tolérées avant élimination), réparties sur 3 tableaux plutôt que 2. Voir l'écran « 3 vies » pour le détail.",
  },
  {
    term: "groupes GSL",
    text: "Format de poule à 4 équipes emprunté à la Global StarCraft League : deux matchs gagnant-gagnant/perdant-perdant puis un match décisif (« decider match ») pour départager les deux dernières places.",
  },
  { term: "spike", text: "La bombe du jeu. Les attaquants doivent la poser sur un site puis la protéger jusqu'à son explosion ; les défenseurs peuvent la désamorcer." },
  { term: "éco", text: "« Économie » : un round où une équipe n'achète presque rien pour garder ses crédits et être mieux équipée au round suivant. Elle perd souvent ce round volontairement." },
  { term: "force buy", text: "Acheter avec tout ce qu'on a, même si l'équipement reste moyen, pour surprendre l'adversaire au lieu d'économiser." },
  { term: "full buy", text: "Un achat complet : les meilleures armes, des boucliers et tous les pouvoirs." },
  { term: "pistol round", text: "Le 1er round de chaque mi-temps : tout le monde commence avec peu de crédits, donc surtout des pistolets." },
  { term: "ultime", text: "Le pouvoir le plus puissant d'un agent. Il se recharge avec le temps et les actions réussies, et peut retourner un round." },
  { term: "ace", text: "Un joueur élimine seul les 5 adversaires pendant un même round." },
  { term: "clutch", text: "Un joueur, seul contre plusieurs adversaires, gagne quand même le round." },
  { term: "retake", text: "Les défenseurs reprennent un site après que les attaquants y ont posé le spike." },
  { term: "ban", text: "Dans le choix des cartes d'un match pro, une équipe élimine une carte qu'elle ne veut pas jouer." },
  { term: "pick", text: "Dans le choix des cartes d'un match pro, une équipe choisit une carte qu'elle veut jouer." },
  // League of Legends (J23) : mots des phrases d'enjeu et du guide.
  {
    term: "phase suisse",
    text: "Format où chaque équipe joue plusieurs rondes contre des adversaires de même bilan. 3 victoires qualifient pour la suite, 3 défaites éliminent : on joue donc au plus 5 matchs.",
  },
  { term: "play-in", text: "Tournoi de qualification avant la phase principale : les équipes les moins bien classées y jouent leur place." },
  { term: "draft", text: "Avant chaque partie, les équipes bannissent puis choisissent à tour de rôle les champions qu'elles vont jouer. Une partie se gagne souvent là." },
  { term: "nexus", text: "La base de chaque équipe. Détruire le nexus adverse gagne la partie." },
  { term: "dragon", text: "Un monstre neutre. Le tuer donne un avantage durable à toute l'équipe ; quatre dragons donnent un bonus très fort." },
  { term: "baron", text: "Le monstre neutre le plus puissant de la carte. L'équipe qui le tue renforce ses soldats et attaque plus facilement les tours." },
  { term: "jungle", text: "Le territoire entre les trois voies, rempli de monstres. Le « jungler » s'y déplace pour aider les autres joueurs par surprise." },
  { term: "side", text: "Le côté de la carte, bleu ou rouge. Le côté bleu choisit son champion en premier à la draft ; le côté rouge choisit en dernier." },
  // Super Smash Bros. Ultimate (J27) : mots du guide et des tournois.
  { term: "stock", text: "Une vie. Chaque joueur en a 3 : quand on est éjecté de l'écran, on perd un stock. Le dernier joueur qui en garde un gagne la manche." },
  { term: "set", text: "Une confrontation entre deux joueurs, jouée en plusieurs manches : la première personne à 2 manches (ou 3 en finale) gagne le set." },
  {
    term: "double élimination",
    text: "On est éliminé à la deuxième défaite, pas à la première. Une première défaite envoie dans le tableau des perdants, où l'on peut encore remonter jusqu'à la finale.",
  },
  { term: "winners", text: "Le tableau des gagnants : on y reste tant qu'on ne perd pas. Son vainqueur arrive en grande finale avec une « vie d'avance »." },
  { term: "losers", text: "Le tableau des perdants : on y tombe après une première défaite. Une seconde défaite élimine du tournoi." },
  { term: "top 8", text: "Les huit derniers joueurs en lice, joués sur scène et diffusés. C'est la partie d'un tournoi que presque tout le monde regarde." },
  { term: "poule", text: "Au début d'un gros tournoi, les joueurs sont répartis en petits tableaux (poules) pour que chacun joue plusieurs sets. Les meilleurs passent à l'étape suivante." },
];

// Structures (J23, #A4) : rattache les équipes déjà en base à leur structure (même nom normalisé dans plusieurs
// jeux). Les nouvelles équipes sont rattachées par le worker à l'ingestion ; ce rattrapage ne sert qu'une fois.
async function backfillOrganizations(prisma: PrismaClient): Promise<number> {
  const teams = await prisma.entity.findMany({ where: { kind: "team", organizationId: null }, select: { id: true, name: true, imageUrl: true } });
  let linked = 0;
  for (const team of teams) {
    const key = organizationKey(team.name);
    if (!key) continue;
    const organization = await prisma.organization.upsert({
      where: { key },
      create: { id: randomUUID(), key, name: team.name, imageUrl: team.imageUrl },
      update: {},
    });
    await prisma.entity.update({ where: { id: team.id }, data: { organizationId: organization.id } });
    linked += 1;
  }
  return linked;
}

async function main() {
  const prisma = new PrismaClient();
  try {
    for (const { term, text } of GLOSSARY_TERMS) {
      await prisma.contextSnippet.upsert({
        where: { targetType_targetId_kind: { targetType: "glossary", targetId: term.toLowerCase(), kind: "definition" } },
        create: { targetType: "glossary", targetId: term.toLowerCase(), kind: "definition", text, generatedBy: "editorial" },
        update: { text, generatedBy: "editorial" },
      });
    }
    console.log(`Glossaire : ${GLOSSARY_TERMS.length} termes à jour.`);
    console.log(`Structures : ${await backfillOrganizations(prisma)} équipes rattachées.`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
