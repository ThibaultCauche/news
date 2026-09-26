import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { createLogger } from "@news/domain";
import { buildCompetitionIntro, LiquipediaClient, parseInfoboxFields } from "@news/providers";
import { PRISMA } from "../db/db.module";
import { LIQUIPEDIA_CLIENT } from "./constants";

const logger = createLogger("worker:liquipedia");

// Rafraîchi ≥24h (docs/03 §3, §7) : contexte d'une compétition ("pourquoi cette
// compétition compte", en-tête écran 01), une phrase gabarit à partir des champs
// structurés de l'infobox Liquipedia — jamais son texte libre, qui resterait en
// anglais (règle CLAUDE.md : textes visibles en français). Attribution CC-BY-SA
// portée par `context_snippet.source`/`license` (docs/03 §7, règle 8 de CLAUDE.md).
const REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000;
const TARGET_TYPE = "competition";
const KIND = "liquipedia_intro";

@Injectable()
export class LiquipediaContextService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    @Inject(LIQUIPEDIA_CLIENT) private readonly client: LiquipediaClient,
  ) {}

  async run(): Promise<void> {
    // `hasBracket` ne se pose que sur des étapes ("Playoffs", "Group C"…) : un
    // nom bien trop générique pour trouver la bonne page Liquipedia (ex. "Group
    // C" tombe sur un tournoi sans rapport). On remonte plutôt au tournoi
    // parent ("Champions 2026"), dont le nom est spécifique — c'est aussi là que
    // l'appli remonte déjà pour la frise de saison (`parentId`, docs/04 J3).
    const stages = await this.prisma.competition.findMany({
      where: { hasBracket: true, status: { in: ["scheduled", "live"] } },
      select: { id: true, name: true, parent: { select: { id: true, name: true } } },
    });
    const targets = new Map<string, string>();
    for (const stage of stages) {
      const target = stage.parent ?? stage;
      targets.set(target.id, target.name);
    }

    let refreshed = 0;
    for (const [competitionId, name] of targets) {
      try {
        if (await this.isFresh(competitionId)) continue;
        if (await this.refresh(competitionId, name)) refreshed += 1;
      } catch (err) {
        // Une compétition en échec (page introuvable, panne réseau…) ne doit pas
        // bloquer les autres — enrichissement, jamais critique (docs/01).
        logger.warn({ err, competitionId, name }, "contexte Liquipedia non mis à jour");
      }
    }
    logger.info({ candidates: targets.size, refreshed }, "contexte Liquipedia synchronisé");
  }

  private async isFresh(competitionId: string): Promise<boolean> {
    const existing = await this.prisma.contextSnippet.findUnique({
      where: { targetType_targetId_kind: { targetType: TARGET_TYPE, targetId: competitionId, kind: KIND } },
      select: { updatedAt: true },
    });
    return existing != null && Date.now() - existing.updatedAt.getTime() < REFRESH_INTERVAL_MS;
  }

  private async refresh(competitionId: string, name: string): Promise<boolean> {
    const pageTitle = await this.client.searchPageTitle(name);
    if (!pageTitle) {
      logger.warn({ competitionId, name }, "aucune page Liquipedia trouvée");
      return false;
    }
    const wikitext = await this.client.fetchInfoboxWikitext(pageTitle);
    const intro = wikitext ? buildCompetitionIntro(parseInfoboxFields(wikitext)) : null;
    if (!intro) {
      logger.warn({ competitionId, name, pageTitle }, "infobox Liquipedia sans champs exploitables");
      return false;
    }

    await this.prisma.contextSnippet.upsert({
      where: { targetType_targetId_kind: { targetType: TARGET_TYPE, targetId: competitionId, kind: KIND } },
      create: { targetType: TARGET_TYPE, targetId: competitionId, kind: KIND, text: intro, source: "Liquipedia", license: "CC-BY-SA", generatedBy: "liquipedia" },
      update: { text: intro, source: "Liquipedia", license: "CC-BY-SA", generatedBy: "liquipedia" },
    });
    return true;
  }
}
