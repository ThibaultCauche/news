import { randomUUID } from "node:crypto";
import { BadRequestException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma, PrismaClient, Subscription } from "@news/db";
import { defaultSubscriptionNotifications, SubscriptionTargetType, SUBSCRIPTION_LEVELS } from "@news/domain";
import { PRISMA } from "../db/db.module";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { CreateSubscriptionDto, FollowStateDto, SubscriptionDto, SubscriptionTargetDto } from "./subscription.dto";

function toSubscriptionDto(sub: Subscription): SubscriptionDto {
  return {
    id: sub.id,
    targetType: sub.targetType,
    targetId: sub.targetId,
    level: sub.level,
    notifyReminder: sub.notifyReminder,
    notifyStart: sub.notifyStart,
    notifyResult: sub.notifyResult,
    muted: sub.muted,
  };
}

// `category` : "seulement les grands moments" par défaut (docs/03 §6, ex. suivre
// toute la catégorie Valorant plutôt qu'une équipe) — le reste démarre à "tout".
function defaultLevel(targetType: string): (typeof SUBSCRIPTION_LEVELS)[number] {
  return targetType === "category" ? "key_moments" : "all";
}

function definedOnly<T extends object>(o: T): Partial<T> {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined)) as Partial<T>;
}

@Injectable()
export class SubscriptionsService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async create(userId: string, dto: CreateSubscriptionDto): Promise<SubscriptionDto> {
    if (dto.muted && dto.targetType !== "competition" && dto.targetType !== "competition_family") {
      throw new BadRequestException("Seule une compétition ou une famille peut être mise en sourdine");
    }
    const data = { muted: dto.muted ?? false, level: dto.level ?? defaultLevel(dto.targetType) };
    // Défauts par cible (J21) à la création seulement : suivre de nouveau, ou mettre en sourdine, ne
    // reprend jamais ce que l'utilisateur a choisi.
    const given = { notifyReminder: dto.notifyReminder, notifyStart: dto.notifyStart, notifyResult: dto.notifyResult };
    const defaults = defaultSubscriptionNotifications(dto.targetType as SubscriptionTargetType);
    const sub = await this.prisma.subscription.upsert({
      where: { userId_targetType_targetId: { userId, targetType: dto.targetType, targetId: dto.targetId } },
      create: { id: randomUUID(), userId, targetType: dto.targetType, targetId: dto.targetId, ...data, ...defaults, ...definedOnly(given) },
      update: { ...data, ...definedOnly(given) },
    });
    if (dto.targetType === "organization") await this.followOrganizationTeams(userId, dto.targetId);
    return toSubscriptionDto(sub);
  }

  // « Suivre toute G2 » (J23, #A4) : un suivi de structure vaut un suivi de chacune de ses équipes, dans tous les
  // jeux. Les équipes qui la rejoignent plus tard sont suivies par le worker (`followOrganizationFor`).
  private async followOrganizationTeams(userId: string, organizationId: string): Promise<void> {
    const teams = await this.prisma.entity.findMany({ where: { organizationId }, select: { id: true } });
    if (teams.length === 0) throw new NotFoundException("Structure introuvable");
    const defaults = defaultSubscriptionNotifications("entity");
    await this.prisma.subscription.createMany({
      data: teams.map((t) => ({ id: randomUUID(), userId, targetType: "entity", targetId: t.id, level: "all", ...defaults })),
      skipDuplicates: true,
    });
  }

  // Idempotent : se désabonner de ce qui ne l'était pas ne fait rien (règle 4 de
  // CLAUDE.md, même logique que l'ingestion).
  async remove(userId: string, dto: SubscriptionTargetDto): Promise<void> {
    if (dto.targetType === "organization") {
      const teams = await this.prisma.entity.findMany({ where: { organizationId: dto.targetId }, select: { id: true } });
      await this.prisma.subscription.deleteMany({ where: { userId, targetType: "entity", targetId: { in: teams.map((t) => t.id) } } });
    }
    await this.prisma.subscription.deleteMany({ where: { userId, targetType: dto.targetType, targetId: dto.targetId } });
  }

  async listWithState(userId: string): Promise<FollowStateDto[]> {
    const subs = await this.prisma.subscription.findMany({ where: { userId }, orderBy: { createdAt: "asc" } });
    if (subs.length === 0) return [];

    const entityIds = subs.filter((s) => s.targetType === "entity").map((s) => s.targetId);
    const organizationIds = subs.filter((s) => s.targetType === "organization").map((s) => s.targetId);
    const [names, currentEvents, entityImages, entityStatuses, organizationImages] = await Promise.all([
      this.resolveNames(subs),
      this.resolveCurrentEvents(subs),
      this.resolveEntityImages(entityIds),
      this.resolveEntityStatuses(entityIds),
      this.resolveOrganizationImages(organizationIds),
    ]);

    return subs.map((sub) => ({
      ...toSubscriptionDto(sub),
      name: names.get(`${sub.targetType}:${sub.targetId}`) ?? "?",
      currentEvent: currentEvents.get(sub.id) ?? null,
      imageUrl: sub.targetType === "entity" ? (entityImages.get(sub.targetId) ?? null) : sub.targetType === "organization" ? (organizationImages.get(sub.targetId) ?? null) : null,
      status: sub.targetType === "entity" ? (entityStatuses.get(sub.targetId) ?? null) : null,
    }));
  }

  private async resolveOrganizationImages(organizationIds: string[]): Promise<Map<string, string | null>> {
    if (organizationIds.length === 0) return new Map();
    const organizations = await this.prisma.organization.findMany({ where: { id: { in: organizationIds } }, select: { id: true, imageUrl: true } });
    return new Map(organizations.map((o) => [o.id, o.imageUrl]));
  }

  private async resolveEntityImages(entityIds: string[]): Promise<Map<string, string | null>> {
    if (entityIds.length === 0) return new Map();
    const entities = await this.prisma.entity.findMany({ where: { id: { in: entityIds } }, select: { id: true, imageUrl: true } });
    return new Map(entities.map((e) => [e.id, e.imageUrl]));
  }

  // "Encore en course" / "Éliminée" pour une équipe suivie (écran Suivis,
  // docs/04 J8) : recalculé depuis `standing` (rempli par le job "structure"
  // du J5), pas de nouveau calcul ici. Une équipe peut avoir des lignes dans
  // plusieurs compétitions (poules puis phase finale) : en pratique un seul
  // tournoi actif à la fois, et si jamais plusieurs lignes existent,
  // l'élimination l'emporte (statut le plus définitif).
  private async resolveEntityStatuses(entityIds: string[]): Promise<Map<string, "qualified" | "eliminated" | null>> {
    if (entityIds.length === 0) return new Map();
    const standings = await this.prisma.standing.findMany({ where: { entityId: { in: entityIds }, qualified: { not: null } } });
    const statuses = new Map<string, "qualified" | "eliminated" | null>();
    for (const s of standings) {
      if (statuses.get(s.entityId) === "eliminated") continue;
      statuses.set(s.entityId, s.qualified ? "qualified" : "eliminated");
    }
    return statuses;
  }

  private async resolveNames(subs: Subscription[]): Promise<Map<string, string>> {
    const ids = (targetType: string) => subs.filter((s) => s.targetType === targetType).map((s) => s.targetId);
    const [categories, competitions, families, entities, organizations, events] = await Promise.all([
      this.prisma.category.findMany({ where: { id: { in: ids("category") } }, select: { id: true, name: true } }),
      this.prisma.competition.findMany({ where: { id: { in: ids("competition") } }, select: { id: true, name: true } }),
      this.prisma.competitionFamily.findMany({ where: { id: { in: ids("competition_family") } }, select: { id: true, name: true } }),
      this.prisma.entity.findMany({ where: { id: { in: ids("entity") } }, select: { id: true, name: true } }),
      this.prisma.organization.findMany({ where: { id: { in: ids("organization") } }, select: { id: true, name: true } }),
      this.prisma.event.findMany({ where: { id: { in: ids("event") } }, select: { id: true, name: true } }),
    ]);
    const names = new Map<string, string>();
    for (const [type, rows] of [
      ["category", categories],
      ["competition", competitions],
      ["competition_family", families],
      ["entity", entities],
      ["organization", organizations],
      ["event", events],
    ] as const) {
      for (const row of rows) names.set(`${type}:${row.id}`, row.name);
    }
    return names;
  }

  // Une compétition suivie couvre ses compétitions filles, à toute profondeur
  // (ex. suivre "VCT 2026" couvre les matchs de "Champions -> Playoffs" en dessous,
  // abonnement hiérarchique de docs/03 §6). Peu de compétitions suivies par
  // utilisateur : un aller-retour par palier de profondeur reste bon marché.
  private async expandCompetitionDescendants(rootIds: string[]): Promise<Map<string, Set<string>>> {
    const map = new Map<string, Set<string>>();
    for (const rootId of rootIds) {
      const ids = new Set<string>([rootId]);
      let frontier = [rootId];
      while (frontier.length > 0) {
        const children = await this.prisma.competition.findMany({ where: { parentId: { in: frontier } }, select: { id: true } });
        frontier = children.map((c) => c.id).filter((id) => !ids.has(id));
        frontier.forEach((id) => ids.add(id));
      }
      map.set(rootId, ids);
    }
    return map;
  }

  // Prépare la correspondance suivis → matchs (hiérarchie, familles, sourdines), partagée
  // par la carte de chaque suivi et par « Aujourd'hui dans tes suivis » (J22).
  private async prepareMatching(allSubs: Subscription[]) {
    // Une sourdine n'est pas un suivi : pas de carte ; elle sert seulement à écarter
    // ses matchs des suivis de ligue ou de famille (J10).
    const mutedCompetitionIds = allSubs.filter((s) => s.muted && s.targetType === "competition").map((s) => s.targetId);
    const subs = allSubs.filter((s) => !s.muted);
    const entityIds = subs.filter((s) => s.targetType === "entity").map((s) => s.targetId);
    const competitionIds = subs.filter((s) => s.targetType === "competition").map((s) => s.targetId);
    const familyIds = subs.filter((s) => s.targetType === "competition_family").map((s) => s.targetId);
    const eventIds = subs.filter((s) => s.targetType === "event").map((s) => s.targetId);
    const categoryIds = subs.filter((s) => s.targetType === "category").map((s) => s.targetId);

    const competitionDescendants = await this.expandCompetitionDescendants(competitionIds);
    // Famille = ses séries (une par édition) et tout ce qu'elles contiennent.
    const familySeries = familyIds.length
      ? await this.prisma.competition.findMany({ where: { familyId: { in: familyIds } }, select: { id: true, familyId: true } })
      : [];
    const familyDescendants = new Map<string, Set<string>>();
    for (const serie of familySeries) {
      const descendants = (await this.expandCompetitionDescendants([serie.id])).get(serie.id) ?? new Set<string>();
      const set = familyDescendants.get(serie.familyId!) ?? new Set<string>();
      descendants.forEach((id) => set.add(id));
      familyDescendants.set(serie.familyId!, set);
    }
    const mutedDescendants = new Set<string>();
    for (const set of (await this.expandCompetitionDescendants(mutedCompetitionIds)).values()) set.forEach((id) => mutedDescendants.add(id));
    const descendantCompetitionIds = [...competitionDescendants.values(), ...familyDescendants.values()].flatMap((set) => [...set]);

    const or: Prisma.EventWhereInput[] = [];
    if (entityIds.length) or.push({ participants: { some: { entityId: { in: entityIds } } } });
    if (descendantCompetitionIds.length) or.push({ competitionId: { in: descendantCompetitionIds } });
    if (eventIds.length) or.push({ id: { in: eventIds } });
    if (categoryIds.length) or.push({ competition: { categoryId: { in: categoryIds } } });
    if (or.length === 0) return null;

    // Champ `categoryId` en plus de `eventSummaryInclude` : nécessaire ici pour
    // faire correspondre les abonnements par catégorie, jamais renvoyé au client
    // (`toEventSummary` reconstruit l'objet champ par champ).
    const include = { ...eventSummaryInclude, competition: { select: { ...eventSummaryInclude.competition.select, categoryId: true } } };

    type Candidate = Prisma.EventGetPayload<{ include: typeof include }>;
    const matches = (sub: Subscription, event: Candidate): boolean => {
      switch (sub.targetType) {
        case "entity":
          return event.participants.some((p) => p.entityId === sub.targetId);
        case "competition":
          return !mutedDescendants.has(event.competitionId) && (competitionDescendants.get(sub.targetId)?.has(event.competitionId) ?? false);
        case "competition_family":
          return !mutedDescendants.has(event.competitionId) && (familyDescendants.get(sub.targetId)?.has(event.competitionId) ?? false);
        case "event":
          return event.id === sub.targetId;
        case "category":
          return event.competition.categoryId === sub.targetId;
        default:
          return false;
      }
    };

    return { or, include, matches, subs };
  }

  // Matchs des suivis dans une fenêtre de temps (J22) : tout statut, le tri par jour se fait côté appli.
  async listEventsInWindow(userId: string, from: Date, to: Date, limit = 80, competition?: Prisma.CompetitionWhereInput): Promise<EventSummaryDto[]> {
    const subs = await this.prisma.subscription.findMany({ where: { userId } });
    const prepared = await this.prepareMatching(subs);
    if (!prepared) return [];
    const events = await this.prisma.event.findMany({
      where: { OR: prepared.or, startsAt: { gte: from, lte: to }, status: { not: "cancelled" }, ...(competition ? { competition } : {}) },
      include: prepared.include,
      orderBy: { startsAt: "asc" },
      take: limit * 2,
    });
    // Une sourdine écarte ses matchs : on ne garde que ceux qu'au moins un suivi actif couvre.
    return events
      .filter((event) => prepared.subs.some((sub) => prepared.matches(sub, event)))
      .slice(0, limit)
      .map(toEventSummary);
  }

  // Une carte par suivi avec son état (docs/02 écran 17/Suivis) : le match en
  // direct s'il y en a un, sinon le plus proche à venir.
  private async resolveCurrentEvents(allSubs: Subscription[]): Promise<Map<string, EventSummaryDto>> {
    const prepared = await this.prepareMatching(allSubs);
    if (!prepared) return new Map();
    const { or, include, matches, subs } = prepared;
    const [live, upcoming] = await Promise.all([
      this.prisma.event.findMany({ where: { OR: or, status: "live" }, include, orderBy: { startsAt: "asc" } }),
      this.prisma.event.findMany({
        where: { OR: or, status: "scheduled", startsAt: { gte: new Date() } },
        include,
        orderBy: { startsAt: "asc" },
      }),
    ]);
    const candidates = [...live, ...upcoming]; // en direct d'abord, puis le plus proche à venir

    const result = new Map<string, EventSummaryDto>();
    for (const sub of subs) {
      const match = candidates.find((event) => matches(sub, event));
      if (match) result.set(sub.id, toEventSummary(match));
    }
    return result;
  }
}
