import { PrismaClient } from "@prisma/client";

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
];

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
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
