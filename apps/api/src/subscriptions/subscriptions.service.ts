import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { Prisma, PrismaClient, Subscription } from "@news/db";
import { SUBSCRIPTION_LEVELS } from "@news/domain";
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
  };
}

// `category` : "seulement les grands moments" par défaut (docs/03 §6, ex. suivre
// toute la catégorie Valorant plutôt qu'une équipe) — le reste démarre à "tout".
function defaultLevel(targetType: string): (typeof SUBSCRIPTION_LEVELS)[number] {
  return targetType === "category" ? "key_moments" : "all";
}

@Injectable()
export class SubscriptionsService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async create(userId: string, dto: CreateSubscriptionDto): Promise<SubscriptionDto> {
    const data = {
      level: dto.level ?? defaultLevel(dto.targetType),
      notifyReminder: dto.notifyReminder ?? true,
      notifyStart: dto.notifyStart ?? true,
      notifyResult: dto.notifyResult ?? true,
    };
    const sub = await this.prisma.subscription.upsert({
      where: { userId_targetType_targetId: { userId, targetType: dto.targetType, targetId: dto.targetId } },
      create: { id: randomUUID(), userId, targetType: dto.targetType, targetId: dto.targetId, ...data },
      update: data,
    });
    return toSubscriptionDto(sub);
  }

  // Idempotent : se désabonner de ce qui ne l'était pas ne fait rien (règle 4 de
  // CLAUDE.md, même logique que l'ingestion).
  async remove(userId: string, dto: SubscriptionTargetDto): Promise<void> {
    await this.prisma.subscription.deleteMany({ where: { userId, targetType: dto.targetType, targetId: dto.targetId } });
  }

  async listWithState(userId: string): Promise<FollowStateDto[]> {
    const subs = await this.prisma.subscription.findMany({ where: { userId }, orderBy: { createdAt: "asc" } });
    if (subs.length === 0) return [];

    const [names, currentEvents] = await Promise.all([this.resolveNames(subs), this.resolveCurrentEvents(subs)]);

    return subs.map((sub) => ({
      ...toSubscriptionDto(sub),
      name: names.get(`${sub.targetType}:${sub.targetId}`) ?? "?",
      currentEvent: currentEvents.get(sub.id) ?? null,
    }));
  }

  private async resolveNames(subs: Subscription[]): Promise<Map<string, string>> {
    const ids = (targetType: string) => subs.filter((s) => s.targetType === targetType).map((s) => s.targetId);
    const [categories, competitions, entities, events] = await Promise.all([
      this.prisma.category.findMany({ where: { id: { in: ids("category") } }, select: { id: true, name: true } }),
      this.prisma.competition.findMany({ where: { id: { in: ids("competition") } }, select: { id: true, name: true } }),
      this.prisma.entity.findMany({ where: { id: { in: ids("entity") } }, select: { id: true, name: true } }),
      this.prisma.event.findMany({ where: { id: { in: ids("event") } }, select: { id: true, name: true } }),
    ]);
    const names = new Map<string, string>();
    for (const [type, rows] of [
      ["category", categories],
      ["competition", competitions],
      ["entity", entities],
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

  // Une carte par suivi avec son état (docs/02 écran 17/Suivis) : le match en
  // direct s'il y en a un, sinon le plus proche à venir.
  private async resolveCurrentEvents(subs: Subscription[]): Promise<Map<string, EventSummaryDto>> {
    const entityIds = subs.filter((s) => s.targetType === "entity").map((s) => s.targetId);
    const competitionIds = subs.filter((s) => s.targetType === "competition").map((s) => s.targetId);
    const eventIds = subs.filter((s) => s.targetType === "event").map((s) => s.targetId);
    const categoryIds = subs.filter((s) => s.targetType === "category").map((s) => s.targetId);

    const competitionDescendants = await this.expandCompetitionDescendants(competitionIds);
    const descendantCompetitionIds = [...competitionDescendants.values()].flatMap((set) => [...set]);

    const or: Prisma.EventWhereInput[] = [];
    if (entityIds.length) or.push({ participants: { some: { entityId: { in: entityIds } } } });
    if (descendantCompetitionIds.length) or.push({ competitionId: { in: descendantCompetitionIds } });
    if (eventIds.length) or.push({ id: { in: eventIds } });
    if (categoryIds.length) or.push({ competition: { categoryId: { in: categoryIds } } });
    if (or.length === 0) return new Map();

    // Champ `categoryId` en plus de `eventSummaryInclude` : nécessaire ici pour
    // faire correspondre les abonnements par catégorie, jamais renvoyé au client
    // (`toEventSummary` reconstruit l'objet champ par champ).
    const include = { ...eventSummaryInclude, competition: { select: { ...eventSummaryInclude.competition.select, categoryId: true } } };
    const [live, upcoming] = await Promise.all([
      this.prisma.event.findMany({ where: { OR: or, status: "live" }, include, orderBy: { startsAt: "asc" } }),
      this.prisma.event.findMany({
        where: { OR: or, status: "scheduled", startsAt: { gte: new Date() } },
        include,
        orderBy: { startsAt: "asc" },
      }),
    ]);
    const candidates = [...live, ...upcoming]; // en direct d'abord, puis le plus proche à venir

    const matches = (sub: Subscription, event: (typeof candidates)[number]): boolean => {
      switch (sub.targetType) {
        case "entity":
          return event.participants.some((p) => p.entityId === sub.targetId);
        case "competition":
          return competitionDescendants.get(sub.targetId)?.has(event.competitionId) ?? false;
        case "event":
          return event.id === sub.targetId;
        case "category":
          return event.competition.categoryId === sub.targetId;
        default:
          return false;
      }
    };

    const result = new Map<string, EventSummaryDto>();
    for (const sub of subs) {
      const match = candidates.find((event) => matches(sub, event));
      if (match) result.set(sub.id, toEventSummary(match));
    }
    return result;
  }
}
