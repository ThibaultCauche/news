import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";

// Textes écrits une fois, pas amenés à changer souvent (`packages/db/prisma/seed.ts`) :
// TTL long, la mise à jour se fait en rejouant le seed plutôt qu'en attendant l'expiration.
const TTL_SECONDS = 3600;

export class GlossaryTermDto {
  @ApiProperty() term!: string;
  @ApiProperty() text!: string;
}

@Injectable()
export class GlossaryService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  // GET /v1/glossary/:term (docs/03 §4, écran 04). Recherche insensible à la
  // casse : les mots repérés `[[terme]]` dans le texte reprennent la casse
  // d'origine (ex. `[[BO3]]`), pas le `target_id` (`bo3`) stocké en base.
  async getByTerm(term: string): Promise<GlossaryTermDto> {
    const key = term.toLowerCase();
    const cacheKey = CacheKeys.glossary(key);
    const cached = await this.cache.get<GlossaryTermDto>(cacheKey);
    if (cached) return cached;

    const snippet = await this.prisma.contextSnippet.findUnique({
      where: { targetType_targetId_kind: { targetType: "glossary", targetId: key, kind: "definition" } },
    });
    if (!snippet) throw new NotFoundException("Terme introuvable");

    const response: GlossaryTermDto = { term: key, text: snippet.text };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
