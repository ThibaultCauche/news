import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { Prisma, PrismaClient } from "@news/db";
import { CompetitionDTO, computeIngestionLatencyMs, computePayloadHash, createLogger, EntityDTO, EventDTO, shouldUpsert } from "@news/domain";
import { PandaScoreProvider } from "@news/providers";
import { PRISMA } from "../db/db.module";
import { PANDASCORE_PROVIDER } from "../pandascore/pandascore.module";
import { commitProviderRef, findProviderRef, upsertByProviderRef } from "./provider-ref.repository";

const CATEGORY_SLUG = "esport";
const PROVIDER_PAYLOAD_RETENTION_DAYS = 7;

const logger = createLogger("worker:ingestion");

// Normalise → upsert via provider_ref + payload_hash (règle 4 de CLAUDE.md).
// Un seul fournisseur au J1 (PandaScore) ; d'autres adaptateurs suivront le même schéma.
@Injectable()
export class IngestionService {
  private categoryId: string | null = null;

  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    @Inject(PANDASCORE_PROVIDER) private readonly provider: PandaScoreProvider,
  ) {}

  private async getCategoryId(): Promise<string> {
    if (this.categoryId) return this.categoryId;
    const category = await this.prisma.category.upsert({
      where: { slug: CATEGORY_SLUG },
      create: { id: randomUUID(), slug: CATEGORY_SLUG, name: "E-sport" },
      update: {},
    });
    this.categoryId = category.id;
    return category.id;
  }

  private async upsertCompetition(dto: CompetitionDTO): Promise<void> {
    const categoryId = await this.getCategoryId();
    let parentId: string | null = null;
    if (dto.parentExternalId) {
      const parentRef = await findProviderRef(this.prisma, dto.provider, "competition", dto.parentExternalId);
      if (!parentRef) {
        logger.warn(
          { externalId: dto.externalId, parentExternalId: dto.parentExternalId },
          "compétition parente introuvable, ignorée pour ce passage",
        );
      }
      parentId = parentRef?.objectId ?? null;
    }

    await upsertByProviderRef(this.prisma, {
      provider: dto.provider,
      objectType: "competition",
      externalId: dto.externalId,
      raw: dto.raw,
      write: async (existingId) => {
        const data = {
          categoryId,
          parentId,
          kind: dto.kind,
          name: dto.name,
          status: dto.status,
          startsAt: dto.startsAt,
          endsAt: dto.endsAt,
          importance: dto.importance,
        };
        if (existingId) {
          await this.prisma.competition.update({ where: { id: existingId }, data });
          return existingId;
        }
        const created = await this.prisma.competition.create({ data: { id: randomUUID(), ...data } });
        return created.id;
      },
    });
  }

  private async upsertEntity(dto: EntityDTO): Promise<string> {
    const { objectId } = await upsertByProviderRef(this.prisma, {
      provider: dto.provider,
      objectType: "entity",
      externalId: dto.externalId,
      raw: dto,
      write: async (existingId) => {
        const data = { kind: dto.kind, name: dto.name, shortName: dto.shortName, imageUrl: dto.imageUrl, region: dto.region };
        if (existingId) {
          await this.prisma.entity.update({ where: { id: existingId }, data });
          return existingId;
        }
        const created = await this.prisma.entity.create({ data: { id: randomUUID(), ...data } });
        return created.id;
      },
    });
    return objectId;
  }

  private async upsertEvent(dto: EventDTO): Promise<void> {
    const existingRef = await findProviderRef(this.prisma, dto.provider, "event", dto.externalId);
    const hash = computePayloadHash(dto.raw);
    if (existingRef && !shouldUpsert(existingRef.payloadHash, hash)) {
      return; // rien n'a changé : on n'écrit rien et on n'émet aucun événement métier
    }

    const competitionRef = await findProviderRef(this.prisma, dto.provider, "competition", dto.competitionExternalId);
    if (!competitionRef) {
      logger.warn(
        { externalId: dto.externalId, competitionExternalId: dto.competitionExternalId },
        "compétition introuvable, événement ignoré pour ce passage",
      );
      return;
    }

    const previousStatus = existingRef
      ? (await this.prisma.event.findUnique({ where: { id: existingRef.objectId }, select: { status: true } }))?.status ?? null
      : null;

    const data = {
      competitionId: competitionRef.objectId,
      kind: dto.kind,
      name: dto.name,
      status: dto.status,
      startsAt: dto.startsAt,
      endsAt: dto.endsAt,
      bestOf: dto.bestOf,
      result: dto.result as Prisma.InputJsonValue,
    };
    const eventId = existingRef?.objectId ?? randomUUID();
    if (existingRef) {
      await this.prisma.event.update({ where: { id: eventId }, data });
    } else {
      await this.prisma.event.create({ data: { id: eventId, spoilerSensitive: true, ...data } });
    }
    await commitProviderRef(this.prisma, {
      provider: dto.provider,
      objectType: "event",
      externalId: dto.externalId,
      objectId: eventId,
      payloadHash: hash,
      raw: dto.raw,
    });

    for (const participant of dto.participants) {
      const entityId = await this.upsertEntity(participant.entity);
      await this.prisma.eventParticipant.upsert({
        where: { eventId_entityId: { eventId, entityId } },
        create: { id: randomUUID(), eventId, entityId, score: participant.score, isWinner: participant.isWinner },
        update: { score: participant.score, isWinner: participant.isWinner },
      });
    }

    // Mesure de la latence réelle début/fin (point ouvert de docs/01, J1).
    if (dto.status === "finished" && previousStatus !== "finished" && dto.endsAt) {
      const latencyMs = computeIngestionLatencyMs(dto.endsAt, new Date());
      logger.info({ externalId: dto.externalId, name: dto.name, latencyMs }, "match terminé détecté");
    }
  }

  async runCatalogue(): Promise<void> {
    const competitions = await this.provider.listCompetitions();
    for (const dto of competitions) {
      await this.upsertCompetition(dto);
    }
    const deleted = await this.prisma.providerPayload.deleteMany({
      where: { fetchedAt: { lt: new Date(Date.now() - PROVIDER_PAYLOAD_RETENTION_DAYS * 24 * 60 * 60 * 1000) } },
    });
    logger.info({ count: competitions.length, purged: deleted.count, quota: this.provider.quota.getUsageRatio() }, "catalogue ingéré");
  }

  async runCalendar(): Promise<void> {
    if (this.provider.quota.shouldThrottle()) {
      logger.warn({ quota: this.provider.quota.getUsageRatio() }, "quota au-delà de 70%, calendrier reporté");
      return;
    }
    const events = await this.provider.listEvents();
    for (const dto of events) {
      await this.upsertEvent(dto);
    }
    logger.info({ count: events.length, quota: this.provider.quota.getUsageRatio() }, "calendrier ingéré");
  }

  // Matchs en cours : rythme rapide, toujours exécuté (règle 5 de CLAUDE.md).
  async runLive(): Promise<void> {
    const events = await this.provider.listEvents({ onlyLive: true });
    for (const dto of events) {
      await this.upsertEvent(dto);
    }
    logger.info({ count: events.length, quota: this.provider.quota.getUsageRatio() }, "matchs en direct ingérés");
  }
}
