import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { ELECTION_KIND, electionEmbargo, isElectionDay, LAW_FORMAT, LawStructure, VOTE_KIND, VoteResult } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";
import { electionById, ElectionCardDto } from "./elections.dto";
import { LawCardDto, outcomeOf, PoliticsOverviewDto } from "./politics.dto";

const TTL_SECONDS = 60;

// Page Politique (J29) : les derniers votes, les textes qui bougent, les dernières lois promulguées. Tout est lu en
// base, jamais chez l'Assemblée (règle 1 de CLAUDE.md).
@Injectable()
export class PoliticsService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getOverview(): Promise<PoliticsOverviewDto> {
    const cached = await this.cache.get<PoliticsOverviewDto>(CacheKeys.politics());
    if (cached) return cached;

    const [votes, laws, electionRows] = await Promise.all([
      this.prisma.event.findMany({ where: { kind: VOTE_KIND }, orderBy: { startsAt: "desc" }, take: 12, select: { id: true, name: true, competitionId: true, competition: { select: { name: true } }, result: true } }),
      this.prisma.competition.findMany({ where: { format: LAW_FORMAT }, select: { id: true, name: true, structure: true, updatedAt: true } }),
      this.prisma.competition.findMany({ where: { kind: ELECTION_KIND }, select: { id: true, name: true, structure: true } }),
    ]);
    const now = new Date();
    const elections: ElectionCardDto[] = electionRows.flatMap((row) => {
      const config = electionById((row.structure as { electionId?: string } | null)?.electionId ?? "");
      if (!config) return [];
      const embargo = electionEmbargo(config.date, now);
      const phase = isElectionDay(config.date, now) ? "tonight" : now < embargo.liftsAt ? "upcoming" : "done";
      return [{ competitionId: row.id, name: row.name, date: config.date, embargoed: embargo.embargoed, liftsAt: embargo.liftsAt.toISOString(), phase }];
    });
    // Les scrutins à venir d'abord (le plus proche en tête), puis les derniers passés.
    const upcoming = elections.filter((e) => e.phase !== "done").sort((a, b) => a.date.localeCompare(b.date));
    const done = elections.filter((e) => e.phase === "done").sort((a, b) => b.date.localeCompare(a.date));

    const cards = laws.map((law): LawCardDto => {
      const s = law.structure as unknown as LawStructure;
      const steps = s.process.steps;
      const dates = steps.flatMap((x) => (x.date ? [x.date] : [])).sort();
      const current = steps.find((x) => x.state === "current");
      return {
        id: law.id,
        name: law.name,
        lawType: s.lawType,
        status: s.process.status,
        stepLabel: s.process.status === "promulgated" ? `Promulgée${s.lawNumber ? ` · loi n° ${s.lawNumber}` : ""}` : s.process.status === "rejected" ? "Texte rejeté" : (current?.label ?? null),
        lastDate: dates.at(-1) ?? null,
      };
    });
    const recent = (a: LawCardDto, b: LawCardDto) => (b.lastDate ?? "").localeCompare(a.lastDate ?? "");

    const response: PoliticsOverviewDto = {
      votes: votes.map((v) => {
        const result = v.result as unknown as VoteResult;
        return { eventId: v.id, name: v.name, date: result.date, outcome: outcomeOf(result), lawId: v.competitionId, lawName: v.competition.name };
      }),
      inProgress: cards.filter((c) => c.status === "in_progress").sort(recent).slice(0, 15),
      promulgated: cards.filter((c) => c.status === "promulgated").sort(recent).slice(0, 10),
      elections: [...upcoming, ...done],
      sourceUpdatedAt: laws.reduce((latest, l) => (l.updatedAt > latest ? l.updatedAt : latest), new Date(0)).toISOString(),
    };
    await this.cache.set(CacheKeys.politics(), response, TTL_SECONDS);
    return response;
  }
}
