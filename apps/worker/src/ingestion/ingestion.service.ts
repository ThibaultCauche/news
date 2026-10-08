import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { Prisma, PrismaClient } from "@news/db";
import {
  BracketFormat,
  categoryOfGame,
  CompetitionDTO,
  buildSwissMatchStakes,
  computeIngestionLatencyMs,
  computePayloadHash,
  computeStandings,
  createLogger,
  detectBracketFormat,
  diffEventStatus,
  diffStandings,
  EntityDTO,
  EventDTO,
  EventStateSnapshot,
  EventStatus,
  familyNameOf,
  defaultSubscriptionNotifications,
  isSwissMatchName,
  organizationKey,
  shouldUpsert,
  StandingDTO,
  StandingMatchInput,
  standingsOptionsFor,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { EventBusService } from "../events/event-bus.service";
import { INGESTION_PROVIDERS, IngestionProvider, IngestionProviders } from "./providers";
import { commitProviderRef, findProviderRef, upsertByProviderRef } from "./provider-ref.repository";

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
// Un adaptateur par fournisseur (PandaScore, start.gg au J27), chacun avec son propre quota.
@Injectable()
export class IngestionService {
  private readonly categoryIds = new Map<string, string>();

  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    @Inject(INGESTION_PROVIDERS) private readonly providers: IngestionProviders,
    private readonly eventBus: EventBusService,
  ) {}

  // Catégorie de la compétition, selon son jeu ou son sport (« E-sport » par défaut, « Sport » pour la F1, J28).
  private async getCategoryId(game: string | null): Promise<string> {
    const { slug, name } = categoryOfGame(game);
    const known = this.categoryIds.get(slug);
    if (known) return known;
    const category = await this.prisma.category.upsert({ where: { slug }, create: { id: randomUUID(), slug, name }, update: {} });
    this.categoryIds.set(slug, category.id);
    return category.id;
  }

  private async upsertCompetition(dto: CompetitionDTO): Promise<void> {
    const categoryId = await this.getCategoryId(dto.game);
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
        const dataWithBracket = { ...data, hasBracket: dto.hasBracket, location: dto.location ?? null };
        if (existingId) {
          await this.prisma.competition.update({ where: { id: existingId }, data: dataWithBracket });
          return existingId;
        }
        const created = await this.prisma.competition.create({ data: { id: randomUUID(), ...dataWithBracket } });
        return created.id;
      },
    });
  }

  private async upsertEntity(dto: EntityDTO, competitionId: string): Promise<string> {
    const { objectId } = await upsertByProviderRef(this.prisma, {
      provider: dto.provider,
      objectType: "entity",
      externalId: dto.externalId,
      raw: dto,
      write: async (existingId) => {
        const organizationId = await this.resolveOrganization(dto);
        const data = { kind: dto.kind, name: dto.name, shortName: dto.shortName, imageUrl: dto.imageUrl, region: dto.region, organizationId };
        if (existingId) {
          const before = await this.prisma.entity.findUnique({ where: { id: existingId }, select: { organizationId: true } });
          await this.prisma.entity.update({ where: { id: existingId }, data });
          if (organizationId && before?.organizationId !== organizationId) await this.followOrganizationFor(organizationId, existingId, competitionId);
          return existingId;
        }
        const created = await this.prisma.entity.create({ data: { id: randomUUID(), ...data } });
        if (organizationId) await this.followOrganizationFor(organizationId, created.id, competitionId);
        return created.id;
      },
    });
    return objectId;
  }

  // Structure d'une équipe (J23, #A4) : « G2 » de Valorant et « G2 » de League of Legends se retrouvent dans la
  // même structure sans rien faire, parce que leurs noms donnent la même clé (`organizationKey`).
  private async resolveOrganization(dto: EntityDTO): Promise<string | null> {
    const key = dto.kind === "team" ? organizationKey(dto.name) : null;
    if (!key) return null;
    const organization = await this.prisma.organization.upsert({
      where: { key },
      create: { id: randomUUID(), key, name: dto.name, imageUrl: dto.imageUrl },
      update: {},
    });
    if (!organization.imageUrl && dto.imageUrl) await this.prisma.organization.update({ where: { id: organization.id }, data: { imageUrl: dto.imageUrl } });
    return organization.id;
  }

  // Une équipe qui rejoint une structure déjà suivie (la même structure arrive dans un nouveau jeu) : ses abonnés
  // la suivent aussi, comme ceux qui ont suivi « toute la structure ».
  private async followOrganizationFor(organizationId: string, entityId: string, competitionId: string): Promise<void> {
    const followers = await this.prisma.subscription.findMany({ where: { targetType: "organization", targetId: organizationId }, select: { userId: true } });
    if (followers.length === 0) return;
    // Une équipe de plus dans une structure déjà suivie : on le dit aux abonnés (notification « organization_joined »).
    await this.eventBus.publish({ type: "OrganizationTeamJoined", entityId, organizationId, competitionId });
    const defaults = defaultSubscriptionNotifications("entity");
    await this.prisma.subscription.createMany({
      data: followers.map((f) => ({ id: randomUUID(), userId: f.userId, targetType: "entity", targetId: entityId, level: "all", ...defaults })),
      skipDuplicates: true,
    });
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
    let previousResult: unknown = null;

    if (!payloadUnchanged) {
      const existingEvent = existingRef
        ? await this.prisma.event.findUnique({ where: { id: existingRef.objectId }, select: { status: true, result: true } })
        : null;
      previousResult = existingEvent?.result ?? null;
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
        streams: dto.streams as unknown as Prisma.InputJsonValue,
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

    // Phase suisse (J23) : pas de bracket chez PandaScore, donc pas de job « structure » ; le format se reconnaît aux
    // noms « Round N: … » et suffit à calculer le classement (3 victoires qualifient, 3 défaites éliminent).
    if (!payloadUnchanged && isSwissMatchName(dto.name)) await this.detectSwiss(competitionRef.objectId);

    // `side` = rang de l'adversaire chez le fournisseur (0 = gauche, 1 = droite) : sans lui, l'ordre
    // des équipes suivait l'ordre physique des lignes et changeait d'un affichage à l'autre (J10).
    for (const [side, participant] of dto.participants.entries()) {
      const entityId = await this.upsertEntity(participant.entity, competitionRef.objectId);
      await this.prisma.eventParticipant.upsert({
        where: { eventId_entityId: { eventId, entityId } },
        create: { id: randomUUID(), eventId, entityId, side, score: participant.score, isWinner: participant.isWinner },
        update: { side, score: participant.score, isWinner: participant.isWinner },
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
      const competition = await this.prisma.competition.findUnique({ where: { id: competitionRef.objectId }, select: { hasBracket: true, format: true } });
      if (competition?.hasBracket) {
        await this.syncStructure(competitionRef.objectId).catch((err) => logger.error(err, "échec de la synchro structure après fin de match"));
      } else if (competition?.format === "swiss") {
        await this.syncStandings(competitionRef.objectId, "swiss").catch((err) => logger.error(err, "échec du classement suisse après fin de match"));
      }
    }

    // Événements métier : l'API s'y abonne pour invalider son cache (docs/03 §3).
    const nextSnapshot: EventStateSnapshot = { status: dto.status, resultHash: dto.result ? computePayloadHash(dto.result) : null };
    for (const type of diffEventStatus(previousSnapshot, nextSnapshot)) {
      await this.eventBus.publish({ type, eventId, competitionId: competitionRef.objectId });
    }
    // Joueurs appelés à leur station (J27) : le signal passe de faux à vrai sur un set qui n'a pas commencé.
    const isCalled = (result: unknown) => (result as { called?: boolean } | null)?.called === true;
    if (previousSnapshot && dto.status === "scheduled" && isCalled(dto.result) && !isCalled(previousResult)) {
      await this.eventBus.publish({ type: "EventCalled", eventId, competitionId: competitionRef.objectId });
    }
  }

  private async detectSwiss(competitionId: string): Promise<void> {
    const competition = await this.prisma.competition.findUnique({ where: { id: competitionId }, select: { format: true } });
    if (competition?.format === "swiss") return;
    const names = await this.prisma.event.findMany({ where: { competitionId }, select: { name: true } });
    if (detectBracketFormat(names) !== "swiss") return;
    await this.prisma.competition.update({ where: { id: competitionId }, data: { format: "swiss" } });
    logger.info({ competitionId }, "phase suisse reconnue");
  }

  // Un fournisseur en panne ne bloque pas les autres : chaque erreur est journalisée, la dernière est relancée à la
  // fin pour que le job apparaisse en échec (et que la supervision le voie).
  private async eachProvider(job: string, run: (name: string, provider: IngestionProvider) => Promise<void>): Promise<void> {
    let failure: unknown = null;
    for (const [name, provider] of Object.entries(this.providers)) {
      try {
        await run(name, provider);
      } catch (err) {
        logger.error({ err, provider: name, job }, "échec d'un fournisseur");
        failure = err;
      }
    }
    if (failure) throw failure;
  }

  async runCatalogue(): Promise<void> {
    await this.eachProvider("catalogue", async (name, provider) => {
      const competitions = await provider.listCompetitions();
      for (const dto of competitions) {
        await this.upsertCompetition(dto);
      }
      logger.info({ provider: name, count: competitions.length, quota: provider.quota.getUsageRatio() }, "catalogue ingéré");
    });
    const deleted = await this.prisma.providerPayload.deleteMany({
      where: { fetchedAt: { lt: new Date(Date.now() - PROVIDER_PAYLOAD_RETENTION_DAYS * 24 * 60 * 60 * 1000) } },
    });
    logger.info({ purged: deleted.count }, "payloads purgés");
  }

  async runCalendar(): Promise<void> {
    await this.eachProvider("calendar", async (name, provider) => {
      if (provider.quota.shouldThrottle()) {
        logger.warn({ provider: name, quota: provider.quota.getUsageRatio() }, "quota au-delà de 70%, calendrier reporté");
        return;
      }
      const events = await provider.listEvents();
      for (const dto of events) {
        await this.upsertEvent(dto);
      }
      logger.info({ provider: name, count: events.length, quota: provider.quota.getUsageRatio() }, "calendrier ingéré");
      await this.syncProviderStandings(name, provider);
    });
  }

  // Classements donnés par la source (F1, J28) : écrits tels quels, sans recalcul depuis nos matchs.
  private async syncProviderStandings(name: string, provider: IngestionProvider): Promise<void> {
    if (!provider.listStandings) return;
    const rows = await provider.listStandings();
    const byCompetition = new Map<string, StandingDTO[]>();
    for (const row of rows) byCompetition.set(row.competitionExternalId, [...(byCompetition.get(row.competitionExternalId) ?? []), row]);
    for (const [externalId, list] of byCompetition) {
      const competitionRef = await findProviderRef(this.prisma, name, "competition", externalId);
      if (!competitionRef) continue;
      const competitionId = competitionRef.objectId;
      const { changed } = await upsertByProviderRef(this.prisma, {
        provider: name,
        objectType: "standing",
        externalId,
        raw: list,
        write: async () => {
          for (const row of list) {
            const entityId = await this.upsertEntity(row.entity, competitionId);
            await this.prisma.standing.upsert({
              where: { competitionId_entityId: { competitionId, entityId } },
              create: { id: randomUUID(), competitionId, entityId, rank: row.rank, points: row.points, wins: row.wins },
              update: { rank: row.rank, points: row.points, wins: row.wins },
            });
          }
          return competitionId;
        },
      });
      if (changed) await this.eventBus.publish({ type: "StandingChanged", competitionId });
    }
    logger.info({ provider: name, count: rows.length }, "classements de la source ingérés");
  }

  // Matchs en cours : rythme rapide, toujours exécuté (règle 5 de CLAUDE.md).
  async runLive(): Promise<void> {
    await this.eachProvider("live", async (name, provider) => {
      const events = await provider.listEvents({ onlyLive: true });
      for (const dto of events) {
        await this.upsertEvent(dto);
      }
      logger.info({ provider: name, count: events.length, quota: provider.quota.getUsageRatio() }, "matchs en direct ingérés");
    });
  }

  // Brackets et classements (J5) : seuls les tournois avec bracket, actifs ou
  // terminés récemment (le temps que la poule/le tableau se stabilise en base).
  async runStructure(): Promise<void> {
    const recentCutoff = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
    // Un tournoi à venir n'est interrogé que la veille de son début (J23) : avec deux jeux, les phases finales encore
    // lointaines coûtaient à elles seules ~100 requêtes par heure sans rien apporter (aucune équipe connue).
    const soon = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const targets = await this.prisma.competition.findMany({
      where: {
        kind: "tournament",
        hasBracket: true,
        OR: [{ status: "live" }, { status: "scheduled", startsAt: { lte: soon } }, { endsAt: { gte: recentCutoff } }],
      },
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
    // Phases suisses sans bracket : classement recalculé depuis nos matchs, sans appel au fournisseur.
    const swissTargets = await this.prisma.competition.findMany({
      where: { kind: "tournament", hasBracket: false, format: "swiss", OR: [{ status: { in: ["scheduled", "live"] } }, { endsAt: { gte: recentCutoff } }] },
      select: { id: true },
    });
    for (const competition of swissTargets) {
      await this.syncStandings(competition.id, "swiss").catch((err) => logger.error({ err, competitionId: competition.id }, "échec du classement suisse"));
    }
    logger.info({ count: targets.length, swiss: swissTargets.length }, "structure ingérée");
  }

  // Liens de bracket : upsert par match (une source a un unique lien "winner" et un
  // unique lien "loser" sortants, règle 4). `changed` (hash du provider_ref) décide
  // si l'événement métier BracketAdvanced est publié.
  private async syncStructure(competitionId: string): Promise<void> {
    const ref = await this.prisma.providerRef.findFirst({ where: { objectType: "competition", objectId: competitionId } });
    const provider = ref ? this.providers[ref.provider] : undefined;
    if (!ref || !provider?.getStructure) return;
    if (provider.quota.shouldThrottle()) {
      logger.warn({ provider: ref.provider, quota: provider.quota.getUsageRatio() }, "quota au-delà de 70%, structure reportée");
      return;
    }
    const structure = await provider.getStructure(ref.externalId);

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

  // Phrase d'enjeu des matchs à venir d'une phase suisse (J23), d'après le bilan actuel des deux équipes : « Match
  // décisif : le vainqueur est qualifié… ». Stockée sur le match pour que les listes (Agenda, Accueil) l'affichent
  // sans recalcul ; seul un changement est écrit.
  private async refreshSwissStakes(competitionId: string, standings: { entityExternalId: string; wins: number; losses: number }[]): Promise<void> {
    const record = new Map(standings.map((s) => [s.entityExternalId, s]));
    const upcoming = await this.prisma.event.findMany({
      where: { competitionId, status: { in: ["scheduled", "live"] } },
      select: { id: true, bestOf: true, stakes: true, participants: { orderBy: { side: "asc" }, select: { entityId: true, entity: { select: { name: true, shortName: true } } } } },
    });
    for (const event of upcoming) {
      if (event.participants.length !== 2) continue;
      const teams = event.participants.map((p) => ({ name: p.entity.shortName ?? p.entity.name, wins: record.get(p.entityId)?.wins ?? 0, losses: record.get(p.entityId)?.losses ?? 0 }));
      const stakes = buildSwissMatchStakes(teams, event.bestOf);
      if (stakes !== event.stakes) await this.prisma.event.update({ where: { id: event.id }, data: { stakes } });
    }
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
    const standings = computeStandings(matches, standingsOptionsFor(format));
    if (format === "swiss") await this.refreshSwissStakes(competitionId, standings);

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
