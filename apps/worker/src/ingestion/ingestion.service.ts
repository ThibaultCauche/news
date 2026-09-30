import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { Prisma, PrismaClient } from "@news/db";
import {
  BracketFormat,
  CompetitionDTO,
  computeIngestionLatencyMs,
  computePayloadHash,
  computeStandings,
  createLogger,
  diffEventStatus,
  diffStandings,
  EntityDTO,
  EventDTO,
  EventStateSnapshot,
  EventStatus,
  familyNameOf,
  GSL_QUALIFIED_COUNT,
  shouldUpsert,
  StandingMatchInput,
} from "@news/domain";
import { PandaScoreProvider } from "@news/providers";
import { PRISMA } from "../db/db.module";
import { EventBusService } from "../events/event-bus.service";
import { PANDASCORE_PROVIDER } from "../pandascore/pandascore.module";
import { commitProviderRef, findProviderRef, upsertByProviderRef } from "./provider-ref.repository";

const CATEGORY_SLUG = "esport";
const PROVIDER_PAYLOAD_RETENTION_DAYS = 7;

// Au moins un lien de bracket n'a pas pu être résolu ce passage (match source
// pas encore en base — course avec le job calendrier/live qui le crée). Fait
// échouer `write()` exprès pour empêcher `upsertByProviderRef` de valider le
// hash du payload : sinon, une fois le match manquant enfin ingéré, le
// prochain passage verrait le même hash (le bracket PandaScore n'a pas
// changé) et abandonnerait ce lien pour toujours — pas un vrai échec, un
// signal "réessayer au prochain passage".
class StructureIncompleteError extends Error {
  constructor(readonly competitionId: string) {
    super(`bracket incomplet pour ${competitionId}, réessai au prochain passage`);
  }
}

const logger = createLogger("worker:ingestion");

// Normalise → upsert via provider_ref + payload_hash (règle 4 de CLAUDE.md).
// Un seul fournisseur au J1 (PandaScore) ; d'autres adaptateurs suivront le même schéma.
@Injectable()
export class IngestionService {
  private categoryId: string | null = null;

  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    @Inject(PANDASCORE_PROVIDER) private readonly provider: PandaScoreProvider,
    private readonly eventBus: EventBusService,
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
        // Famille d'une série (J10) : « Champions 2027 » rejoint « Champions » dès son ingestion,
        // donc les abonnés à la famille la suivent sans rien faire.
        let familyId: string | null = null;
        const familyName = dto.kind === "serie" && parentId ? familyNameOf(dto.name) : null;
        if (familyName && parentId) {
          const family = await this.prisma.competitionFamily.upsert({
            where: { leagueId_name: { leagueId: parentId, name: familyName } },
            create: { id: randomUUID(), leagueId: parentId, name: familyName },
            update: {},
          });
          familyId = family.id;
        }
        const data = {
          categoryId,
          parentId,
          familyId,
          kind: dto.kind,
          game: dto.game,
          imageUrl: dto.imageUrl,
          name: dto.name,
          status: dto.status,
          startsAt: dto.startsAt,
          endsAt: dto.endsAt,
          importance: dto.importance,
        };
        const dataWithBracket = { ...data, hasBracket: dto.hasBracket };
        if (existingId) {
          await this.prisma.competition.update({ where: { id: existingId }, data: dataWithBracket });
          return existingId;
        }
        const created = await this.prisma.competition.create({ data: { id: randomUUID(), ...dataWithBracket } });
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
    // "Rien n'a changé" ne doit sauter que l'écriture des champs de l'événement
    // et les événements métier — pas la boucle participants juste en dessous :
    // un événement ingéré avant qu'elle n'existe ne la rejouerait sinon jamais
    // tant que son payload PandaScore ne change plus (cas courant d'un match
    // déjà `finished`), laissant `event_participant` vide pour de bon (règle 4
    // ne dit "on n'écrit rien" que pour ce qui a déjà été écrit).
    const payloadUnchanged = Boolean(existingRef) && !shouldUpsert(existingRef!.payloadHash, hash);

    const competitionRef = await findProviderRef(this.prisma, dto.provider, "competition", dto.competitionExternalId);
    if (!competitionRef) {
      logger.warn(
        { externalId: dto.externalId, competitionExternalId: dto.competitionExternalId },
        "compétition introuvable, événement ignoré pour ce passage",
      );
      return;
    }

    const eventId = existingRef?.objectId ?? randomUUID();
    let previousSnapshot: EventStateSnapshot | null = null;

    if (!payloadUnchanged) {
      const existingEvent = existingRef
        ? await this.prisma.event.findUnique({ where: { id: existingRef.objectId }, select: { status: true, result: true } })
        : null;
      previousSnapshot = existingEvent
        ? { status: existingEvent.status as EventDTO["status"], resultHash: existingEvent.result ? computePayloadHash(existingEvent.result) : null }
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
    }

    for (const participant of dto.participants) {
      const entityId = await this.upsertEntity(participant.entity);
      await this.prisma.eventParticipant.upsert({
        where: { eventId_entityId: { eventId, entityId } },
        create: { id: randomUUID(), eventId, entityId, score: participant.score, isWinner: participant.isWinner },
        update: { score: participant.score, isWinner: participant.isWinner },
      });
    }

    if (payloadUnchanged) return;

    // Mesure de la latence réelle début/fin (point ouvert de docs/01, J1).
    if (dto.status === "finished" && previousSnapshot?.status !== "finished") {
      if (dto.endsAt) {
        const latencyMs = computeIngestionLatencyMs(dto.endsAt, new Date());
        logger.info({ externalId: dto.externalId, name: dto.name, latencyMs }, "match terminé détecté");
      }
      // Structure (bracket/classement) : pas d'attente du prochain passage du job
      // "structure" (5 min) pour un match qui vient de se terminer (docs/03 §3).
      const competition = await this.prisma.competition.findUnique({ where: { id: competitionRef.objectId }, select: { hasBracket: true } });
      if (competition?.hasBracket) {
        await this.syncStructure(competitionRef.objectId).catch((err) => logger.error(err, "échec de la synchro structure après fin de match"));
      }
    }

    // Événements métier : l'API s'y abonne pour invalider son cache (docs/03 §3).
    const nextSnapshot: EventStateSnapshot = { status: dto.status, resultHash: dto.result ? computePayloadHash(dto.result) : null };
    for (const type of diffEventStatus(previousSnapshot, nextSnapshot)) {
      await this.eventBus.publish({ type, eventId, competitionId: competitionRef.objectId });
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

  // Brackets et classements (J5) : seuls les tournois avec bracket, actifs ou
  // terminés récemment (le temps que la poule/le tableau se stabilise en base).
  async runStructure(): Promise<void> {
    if (this.provider.quota.shouldThrottle()) {
      logger.warn({ quota: this.provider.quota.getUsageRatio() }, "quota au-delà de 70%, structure reportée");
      return;
    }
    const recentCutoff = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
    const targets = await this.prisma.competition.findMany({
      where: { kind: "tournament", hasBracket: true, OR: [{ status: { in: ["scheduled", "live"] } }, { endsAt: { gte: recentCutoff } }] },
      select: { id: true },
    });
    for (const competition of targets) {
      await this.syncStructure(competition.id).catch((err) => {
        if (err instanceof StructureIncompleteError) {
          logger.warn({ competitionId: competition.id }, "bracket incomplet, réessai au prochain passage");
          return;
        }
        logger.error({ err, competitionId: competition.id }, "échec de la synchro structure");
      });
    }
    logger.info({ count: targets.length, quota: this.provider.quota.getUsageRatio() }, "structure ingérée");
  }

  // Liens de bracket : upsert par match (une source a un unique lien "winner" et un
  // unique lien "loser" sortants, règle 4). `changed` (hash du provider_ref) décide
  // si l'événement métier BracketAdvanced est publié.
  private async syncStructure(competitionId: string): Promise<void> {
    const ref = await this.prisma.providerRef.findFirst({ where: { objectType: "competition", objectId: competitionId } });
    if (!ref) return;
    const structure = await this.provider.getStructure(ref.externalId);

    const { changed } = await upsertByProviderRef(this.prisma, {
      provider: ref.provider,
      objectType: "bracket",
      externalId: ref.externalId,
      raw: structure,
      write: async () => {
        let incomplete = false;
        for (const link of structure.links) {
          const [fromRef, toRef] = await Promise.all([
            findProviderRef(this.prisma, ref.provider, "event", link.fromExternalId),
            findProviderRef(this.prisma, ref.provider, "event", link.toExternalId),
          ]);
          if (!fromRef || !toRef) {
            logger.warn({ link, competitionId }, "match introuvable pour ce lien de bracket, ignoré pour ce passage");
            incomplete = true;
            continue;
          }
          await this.prisma.eventLink.upsert({
            where: { fromEventId_outcome: { fromEventId: fromRef.objectId, outcome: link.outcome } },
            create: { id: randomUUID(), fromEventId: fromRef.objectId, toEventId: toRef.objectId, outcome: link.outcome, slot: link.slot },
            update: { toEventId: toRef.objectId, slot: link.slot },
          });
        }
        await this.prisma.competition.update({ where: { id: competitionId }, data: { format: structure.format } });
        // Ne pas laisser `upsertByProviderRef` valider le hash de ce passage
        // incomplet — voir `StructureIncompleteError`.
        if (incomplete) throw new StructureIncompleteError(competitionId);
        return competitionId;
      },
    });
    if (changed) await this.eventBus.publish({ type: "BracketAdvanced", competitionId });

    await this.syncStandings(competitionId, structure.format);
  }

  // Classements recalculés depuis nos event/event_participant (règle : le standings
  // gratuit de PandaScore ne donne que le rang, docs/01). `maxLives` généralise le
  // nombre de défaites tolérées selon le format (docs/03 §2).
  private async syncStandings(competitionId: string, format: BracketFormat): Promise<void> {
    const events = await this.prisma.event.findMany({
      where: { competitionId },
      select: { status: true, participants: { select: { entityId: true, score: true, isWinner: true } } },
    });
    const matches: StandingMatchInput[] = events.map((e) => ({
      status: e.status as EventStatus,
      participants: e.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })),
    }));
    const maxLives = format === "triple_elim" ? 3 : format === "single_elim" ? 1 : 2;
    const qualifiedCount = format === "groups_gsl" ? GSL_QUALIFIED_COUNT : undefined;
    const standings = computeStandings(matches, { maxLives, qualifiedCount });

    // Avant d'écrire : l'ancien classement sert à détecter qui vient de passer
    // qualifié ou d'être éliminé (notifications "qualification"/"élimination",
    // docs/03 §6, reportées du J4 au J5).
    const previousRows = await this.prisma.standing.findMany({ where: { competitionId }, select: { entityId: true, qualified: true, livesLeft: true } });
    const { qualifiedEntityIds, eliminatedEntityIds } = diffStandings(
      previousRows,
      standings.map((s) => ({ entityId: s.entityExternalId, qualified: s.qualified, livesLeft: s.livesLeft })),
    );

    const { changed } = await upsertByProviderRef(this.prisma, {
      provider: "pandascore",
      objectType: "standing",
      externalId: competitionId,
      raw: standings,
      write: async () => {
        for (const s of standings) {
          await this.prisma.standing.upsert({
            where: { competitionId_entityId: { competitionId, entityId: s.entityExternalId } },
            create: { id: randomUUID(), competitionId, entityId: s.entityExternalId, rank: s.rank, wins: s.wins, losses: s.losses, livesLeft: s.livesLeft, qualified: s.qualified },
            update: { rank: s.rank, wins: s.wins, losses: s.losses, livesLeft: s.livesLeft, qualified: s.qualified },
          });
        }
        return competitionId;
      },
    });
    if (changed) {
      await this.eventBus.publish({ type: "StandingChanged", competitionId });
      for (const entityId of qualifiedEntityIds) await this.eventBus.publish({ type: "EntityQualified", competitionId, entityId });
      for (const entityId of eliminatedEntityIds) await this.eventBus.publish({ type: "EntityEliminated", competitionId, entityId });
    }
  }
}
