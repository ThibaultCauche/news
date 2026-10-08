import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import {
  buildNotificationText,
  isPracticeSession,
  notificationSubject,
  sessionHasWinner,
  competitionSpecificity,
  createLogger,
  DomainEventMessage,
  DOMAIN_EVENT_NOTIFICATION_TYPES,
  GAME_NAMES,
  isQuietHour,
  isTypeEnabled,
  KEY_MOMENT_MIN_IMPORTANCE,
  localHourFromOffsetMinutes,
  MAX_NOTIFICATIONS_PER_HOUR,
  nearestCompetitionRule,
  NotificationType,
  shouldNotify,
  SubscriptionLevel,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";

const logger = createLogger("worker:notifications");

// 3ᵉ consommateur des événements métier, à côté du cache (docs/03 §3/§6) : qui
// est concerné -> réglages -> déduplication -> envoi FCM -> journal.
@Injectable()
export class NotificationDispatchService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
  ) {}

  async handle(message: DomainEventMessage): Promise<void> {
    const type = DOMAIN_EVENT_NOTIFICATION_TYPES[message.type];
    // EventScheduled/ScoreChanged/BracketAdvanced/StandingChanged : pas de type de
    // notif direct (J4/J5).
    if (!type) return;

    if (type === "qualification" || type === "elimination" || type === "organization_joined") {
      return this.handleEntityNotification(message, type);
    }
    if (!message.eventId) return;

    const event = await this.prisma.event.findUnique({
      where: { id: message.eventId },
      include: { competition: { select: { id: true, name: true, categoryId: true } }, participants: { include: { entity: { select: { name: true, imageUrl: true } } }, orderBy: { side: "asc" } } },
    });
    if (!event) return;

    // F1 (J28) : seule une course ou un sprint a un vainqueur ; les qualifications ont une pole, pas une victoire.
    const hasWinner = event.kind !== "session" || sessionHasWinner(event.name);
    const winnerName = hasWinner ? (event.participants.find((p) => p.isWinner)?.entity.name ?? null) : null;
    const subject = notificationSubject(event, event.competition.name);
    // Les essais libres n'ont ni classement ni enjeu : seul qui les a demandés (la cloche d'une session) est prévenu.
    const practice = event.kind === "session" && isPracticeSession(event.name);
    const entityIds = event.participants.map((p) => p.entityId);
    // F1 (J28) : une écurie n'est pas un participant, mais le classement d'une session dit laquelle a roulé ;
    // qui la suit est prévenu du résultat comme qui suit un de ses pilotes.
    const constructorRefs = (event.result as { rows?: { constructorId?: string }[] } | null)?.rows?.flatMap((r) => (r.constructorId ? [`constructor:${r.constructorId}`] : [])) ?? [];
    if (constructorRefs.length > 0) {
      const refs = await this.prisma.providerRef.findMany({ where: { objectType: "entity", externalId: { in: [...new Set(constructorRefs)] } }, select: { objectId: true } });
      entityIds.push(...refs.map((r) => r.objectId));
    }
    const chain = await this.getCompetitionChain(event.competition.id);
    const competitionIds = chain.map((c) => c.id);
    // Famille de la série du match (J10) : rang dans la chaîne, pour la précision de la règle.
    const familyIndex = chain.findIndex((c) => c.familyId !== null);
    const familyId = familyIndex >= 0 ? chain[familyIndex].familyId : null;

    // Abonnements directs (événement, équipe) et hiérarchiques (compétition
    // parente, famille, catégorie) — docs/03 §6.
    const candidates = await this.prisma.subscription.findMany({
      where: {
        OR: [
          { targetType: "event", targetId: event.id },
          { targetType: "entity", targetId: { in: entityIds } },
          { targetType: "competition", targetId: { in: competitionIds } },
          ...(familyId ? [{ targetType: "competition_family", targetId: familyId }] : []),
          { targetType: "category", targetId: event.competition.categoryId },
        ],
      },
      include: { user: { include: { setting: true, devices: true } } },
    });

    // Pour les compétitions et familles, la règle la plus proche du match l'emporte, par
    // utilisateur (J10) : une série en sourdine coupe l'alerte due à la ligue qu'il suit,
    // sans toucher à ce qui vient d'une équipe ou d'un match suivi.
    const subscriptions = candidates.filter((s) => s.targetType !== "competition" && s.targetType !== "competition_family");
    const rulesByUser = new Map<string, { sub: (typeof candidates)[number]; specificity: number; muted: boolean }[]>();
    for (const sub of candidates) {
      if (sub.targetType !== "competition" && sub.targetType !== "competition_family") continue;
      const specificity =
        sub.targetType === "competition_family"
          ? competitionSpecificity("family", familyIndex)
          : competitionSpecificity("competition", competitionIds.indexOf(sub.targetId));
      const rules = rulesByUser.get(sub.userId) ?? [];
      rules.push({ sub, specificity, muted: sub.muted });
      rulesByUser.set(sub.userId, rules);
    }
    for (const rules of rulesByUser.values()) {
      const nearest = nearestCompetitionRule(rules);
      if (nearest && !nearest.muted) subscriptions.push(nearest.sub);
    }

    for (const sub of subscriptions) {
      if (practice && sub.targetType !== "event") continue;
      const subEnabled = type === "reminder" ? sub.notifyReminder : type === "start" || type === "called" ? sub.notifyStart : sub.notifyResult;
      // Le rappel T-15 absorbe l'ancien rappel de pronostic (J21) : sans pronostic, il part même si le
      // rappel simple est coupé, avec la phrase qui le dit.
      const needsPrediction = type === "reminder" && event.participants.length === 2 && (await this.needsPredictionNudge(sub.user, event.id));
      if (!shouldNotify({ notifyEnabled: subEnabled || needsPrediction, subscriptionLevel: sub.level as SubscriptionLevel, eventImportance: event.importance })) continue;
      if (!needsPrediction && !isTypeEnabled(type, sub.user.setting)) continue;

      // "hors équipe suivie en direct" (docs/03 §6) : un abonnement direct
      // (équipe/événement) n'est jamais plafonné, un abonnement large (catégorie/
      // compétition) l'est.
      const bypassRateLimit = sub.targetType === "entity" || sub.targetType === "event";
      if (!bypassRateLimit) {
        const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
        const recent = await this.prisma.notificationLog.count({ where: { userId: sub.userId, sentAt: { gte: oneHourAgo } } });
        if (recent >= MAX_NOTIFICATIONS_PER_HOUR) continue;
      }

      // Déduplication (règle 4 de CLAUDE.md) : on écrit le journal avant d'envoyer.
      // La contrainte unique (userId, eventId, type) fait foi, pas un check-then-act
      // — deux abonnements qui pointent vers le même événement, ou un traitement
      // concurrent, ne peuvent pas envoyer deux fois.
      try {
        await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: sub.userId, eventId: event.id, type } });
      } catch (err) {
        if ((err as { code?: string }).code === "P2002") continue; // déjà notifié
        throw err;
      }

      const { title, body } = buildNotificationText(type, subject, sub.user.setting?.spoilerFree ?? false, winnerName, needsPrediction);
      // Un tag par match : rappel, début et résultat se remplacent dans le volet (J21). Plusieurs matchs
      // qui commencent ensemble restent une notification chacun (la sienne remplace son rappel) :
      // Android les range lui-même sous « Keryx ».
      const tag = `event-${event.id}`;
      // Logo de l'équipe en petite icône (J22) : celui de l'équipe de gauche (sa place, pas son résultat).
      // Au résultat, hors sans spoil, c'est celui du vainqueur ; en sans spoil on reste sur l'équipe de gauche,
      // qui ne dit pas qui a gagné.
      const spoilerFree = sub.user.setting?.spoilerFree ?? false;
      const first = event.participants[0]?.entity.imageUrl ?? null;
      const image = type === "result" && !spoilerFree ? (event.participants.find((p) => p.isWinner)?.entity.imageUrl ?? first) : first;
      for (const device of sub.user.devices) {
        if (
          device.utcOffsetMinutes !== null &&
          isQuietHour(
            localHourFromOffsetMinutes(new Date(), device.utcOffsetMinutes),
            sub.user.setting?.quietHoursStart ?? null,
            sub.user.setting?.quietHoursEnd ?? null,
          )
        ) {
          continue; // regroupement dans un résumé du matin : écran Réglages pas encore construit (J6)
        }
        if (!device.pushToken) continue;
        const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, { eventId: event.id }, tag, image ?? undefined);
        if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
      }
      logger.info({ userId: sub.userId, eventId: event.id, type }, "notification traitée");
    }
  }

  // Pseudo (compte complet), réglage actif et pas de pronostic sur ce match.
  private async needsPredictionNudge(user: { id: string; pseudo: string | null; setting: { notifyPredictionReminders: boolean } | null }, eventId: string): Promise<boolean> {
    if (!user.pseudo || user.setting?.notifyPredictionReminders === false) return false;
    return (await this.prisma.prediction.count({ where: { userId: user.id, eventId } })) === 0;
  }

  // Qualification/élimination (J5, reporté du J4) : pas de match derrière, donc
  // pas d'abonnement hiérarchique (catégorie/compétition) — seuls les abonnés
  // directs à cette équipe sont concernés (règle 5 de CLAUDE.md, même esprit).
  // Toujours traité comme un "grand moment" et jamais plafonné, comme les autres
  // abonnements directs. La déduplication est par compétition (J23) : une équipe peut être
  // éliminée de plusieurs compétitions, chacune mérite sa notification.
  // `organization_joined` (J23) : une équipe rejoint une structure suivie (même nom dans un nouveau jeu) ;
  // les abonnés sont ceux de la structure.
  private async handleEntityNotification(message: DomainEventMessage, type: NotificationType): Promise<void> {
    const entityId = message.entityId;
    if (!entityId) return;
    const entity = await this.prisma.entity.findUnique({ where: { id: entityId }, select: { name: true } });
    if (!entity) return;

    const joined = type === "organization_joined";
    const organization = joined && message.organizationId ? await this.prisma.organization.findUnique({ where: { id: message.organizationId }, select: { name: true } }) : null;
    if (joined && !organization) return;
    const context = joined ? await this.gameNameOf(message.competitionId) : await this.competitionLabelOf(message.competitionId);

    const subscriptions = await this.prisma.subscription.findMany({
      where: joined ? { targetType: "organization", targetId: message.organizationId } : { targetType: "entity", targetId: entityId },
      include: { user: { include: { setting: true, devices: true } } },
    });

    for (const sub of subscriptions) {
      // Pas de réglage dédié qualification/élimination au J5 : réutilise "résultat".
      const notifyEnabled = sub.notifyResult;
      if (!shouldNotify({ notifyEnabled, subscriptionLevel: sub.level as SubscriptionLevel, eventImportance: KEY_MOMENT_MIN_IMPORTANCE })) continue;
      if (!isTypeEnabled(type, sub.user.setting)) continue;

      try {
        await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: sub.userId, entityId, competitionId: message.competitionId, type } });
      } catch (err) {
        if ((err as { code?: string }).code === "P2002") continue; // déjà notifié
        throw err;
      }

      const { title, body } = buildNotificationText(type, organization?.name ?? entity.name, sub.user.setting?.spoilerFree ?? false, null, false, context);
      for (const device of sub.user.devices) {
        if (
          device.utcOffsetMinutes !== null &&
          isQuietHour(
            localHourFromOffsetMinutes(new Date(), device.utcOffsetMinutes),
            sub.user.setting?.quietHoursStart ?? null,
            sub.user.setting?.quietHoursEnd ?? null,
          )
        ) {
          continue;
        }
        if (!device.pushToken) continue;
        const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, { entityId });
        if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
      }
      logger.info({ userId: sub.userId, entityId, type }, "notification traitée");
    }
  }

  // « Worlds 2026 » pour une étape « Group Stage » : le nom de la série, plus parlant que celui de l'étape.
  private async competitionLabelOf(competitionId: string): Promise<string | null> {
    const competition = await this.prisma.competition.findUnique({ where: { id: competitionId }, select: { name: true, kind: true, parent: { select: { name: true } } } });
    if (!competition) return null;
    return competition.kind === "tournament" && competition.parent ? competition.parent.name : competition.name;
  }

  private async gameNameOf(competitionId: string): Promise<string | null> {
    const competition = await this.prisma.competition.findUnique({ where: { id: competitionId }, select: { game: true } });
    return competition?.game ? (GAME_NAMES[competition.game] ?? null) : null;
  }

  // Chaîne de compétitions d'un match, de la sienne (rang 0) jusqu'à la ligue racine.
  async getCompetitionChain(competitionId: string): Promise<{ id: string; familyId: string | null }[]> {
    const chain: { id: string; familyId: string | null }[] = [];
    let currentId: string | null = competitionId;
    while (currentId) {
      const row: { id: string; parentId: string | null; familyId: string | null } | null = await this.prisma.competition.findUnique({
        where: { id: currentId },
        select: { id: true, parentId: true, familyId: true },
      });
      if (!row) break;
      chain.push({ id: row.id, familyId: row.familyId });
      currentId = row.parentId;
    }
    return chain;
  }
}
