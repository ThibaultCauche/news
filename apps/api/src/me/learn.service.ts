import { BadRequestException, Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { PRISMA } from "../db/db.module";
import { LearnProgressDto, LearnProgressEntryDto } from "./learn.dto";

// Les identifiants viennent des fichiers de tutos de l'appli (`assets/learn/*.json`) : de courts
// slugs. Le plafond évite qu'un client malveillant remplisse la table avec des identifiants inventés.
const SLUG = /^[a-z0-9-]{1,40}$/;
const MAX_ENTRIES_PER_USER = 200;

// Progression dans les tutos (J12), liée au compte : un simple compteur (tutos ouverts, quiz réussis),
// sans points ni classement. Le serveur ne connaît pas les bonnes réponses : « quiz réussi » est
// déclaré par l'appli (voir « Plus tard » dans docs/04 pour la version avec points).
@Injectable()
export class LearnService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async get(userId: string): Promise<LearnProgressDto> {
    const rows = await this.prisma.learnProgress.findMany({ where: { userId }, orderBy: { firstReadAt: "asc" } });
    return { entries: rows.map((r) => ({ guide: r.guide, articleId: r.articleId, quizPassed: r.quizPassed })) };
  }

  async put(userId: string, guide: string, articleId: string, quizPassed?: boolean): Promise<LearnProgressEntryDto> {
    if (!SLUG.test(guide) || !SLUG.test(articleId)) throw new BadRequestException("Identifiant de tuto invalide");
    const where = { userId_guide_articleId: { userId, guide, articleId } };
    if (!(await this.prisma.learnProgress.findUnique({ where })) && (await this.prisma.learnProgress.count({ where: { userId } })) >= MAX_ENTRIES_PER_USER) {
      throw new BadRequestException("Trop de tutos enregistrés");
    }
    // Un quiz réussi ne repasse jamais à « non réussi » (rejouer le quiz et se tromper n'annule rien).
    const row = await this.prisma.learnProgress.upsert({
      where,
      create: { userId, guide, articleId, quizPassed: quizPassed === true },
      update: quizPassed === true ? { quizPassed: true } : {},
    });
    return { guide: row.guide, articleId: row.articleId, quizPassed: row.quizPassed };
  }
}
