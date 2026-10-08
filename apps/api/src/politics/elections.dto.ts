import { ApiProperty } from "@nestjs/swagger";
import { electionEmbargo, ElectionConfig, ElectionList, ElectionResult, ELECTIONS, electionLabel, majoritySeats } from "@news/domain";

// Élections (J29c) : résultats officiels du ministère de l'Intérieur. Tout passe par `electionEmbargo` : le jour du
// scrutin avant 20 h (heure de Paris), l'API ne renvoie aucun résultat (article L52-2), quoi que demande le client.

export class ElectionListDto {
  @ApiProperty() panel!: number;
  @ApiProperty() label!: string;
  @ApiProperty({ nullable: true, type: String }) head!: string | null;
  @ApiProperty() votes!: number;
  @ApiProperty() pctExpressed!: number;
  @ApiProperty() elected!: boolean;
  /** Sièges au conseil municipal (0 tant qu'ils ne sont pas attribués). */
  @ApiProperty() seatsCouncil!: number;
  @ApiProperty() seatsCommunity!: number;
}

export class BureauxDto {
  @ApiProperty() counted!: number;
  @ApiProperty() total!: number;
}

export class ElectionResultDto {
  @ApiProperty({ enum: ["commune", "department", "national"] }) level!: string;
  /** Les « listes » sont des candidats (présidentielle) : ni sièges ni tête de liste. */
  @ApiProperty() candidates!: boolean;
  /** Bureaux de vote dépouillés, quand le fichier par bureau est lu. */
  @ApiProperty({ nullable: true, type: BureauxDto }) bureaux!: BureauxDto | null;
  @ApiProperty() territoryCode!: string;
  @ApiProperty() territoryName!: string;
  @ApiProperty() department!: string;
  @ApiProperty() registered!: number;
  @ApiProperty() voters!: number;
  @ApiProperty() turnoutPct!: number;
  @ApiProperty() blank!: number;
  @ApiProperty() nulls!: number;
  @ApiProperty() expressed!: number;
  @ApiProperty({ type: [ElectionListDto] }) lists!: ElectionListDto[];
  /** Total des sièges attribués au conseil, 0 si aucun. */
  @ApiProperty() totalSeats!: number;
  /** Sièges de la majorité absolue, `null` sans sièges attribués. */
  @ApiProperty({ nullable: true, type: Number }) majoritySeats!: number | null;
  /** Les chiffres sont définitifs ; sinon le dépouillement continue. */
  @ApiProperty() complete!: boolean;
  @ApiProperty() sourceUrl!: string;
}

export class ElectionDto {
  @ApiProperty() electionId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() round!: number;
  @ApiProperty() date!: string;
  /** Vrai le jour du scrutin avant 20 h : aucun résultat n'est donné. */
  @ApiProperty() embargoed!: boolean;
  @ApiProperty() liftsAt!: string;
  /** Absent tant que `embargoed`. */
  @ApiProperty({ nullable: true, type: ElectionResultDto }) result!: ElectionResultDto | null;
}

export class ElectionTerritoryDto {
  @ApiProperty() eventId!: string;
  @ApiProperty({ enum: ["commune", "department", "national"] }) level!: string;
  @ApiProperty() name!: string;
  @ApiProperty() department!: string;
  @ApiProperty() registered!: number;
  @ApiProperty() turnoutPct!: number;
  /** Liste arrivée en tête et son score (% des exprimés), pour la ligne de la liste. */
  @ApiProperty({ nullable: true, type: String }) leaderLabel!: string | null;
  @ApiProperty({ nullable: true, type: Number }) leaderPct!: number | null;
  @ApiProperty() complete!: boolean;
}

// Page d'une élection : sa date, le compte à rebours du blocage, et les territoires suivis une fois les résultats publics.
export class ElectionOverviewDto {
  @ApiProperty() electionId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ enum: ["municipales", "presidentielle"] }) type!: string;
  @ApiProperty() round!: number;
  @ApiProperty() date!: string;
  @ApiProperty() embargoed!: boolean;
  @ApiProperty() liftsAt!: string;
  /** Un jeu de données est branché : sinon « les résultats arriveront ici le soir du scrutin ». */
  @ApiProperty() hasResults!: boolean;
  /** Résultat de la France entière (présidentielle), absent avant 20 h et pour les municipales. */
  @ApiProperty({ nullable: true, type: ElectionResultDto }) national!: ElectionResultDto | null;
  @ApiProperty({ type: [ElectionTerritoryDto] }) territories!: ElectionTerritoryDto[];
}

export class ElectionCardDto {
  @ApiProperty() competitionId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() date!: string;
  @ApiProperty() embargoed!: boolean;
  @ApiProperty() liftsAt!: string;
  /** Pas encore voté, voté aujourd'hui, ou passé. */
  @ApiProperty({ enum: ["upcoming", "tonight", "done"] }) phase!: string;
}

export const electionById = (id: string): ElectionConfig | undefined => ELECTIONS.find((e) => e.id === id);

const listDto = (l: ElectionList): ElectionListDto => ({ ...l });

export function toElectionResultDto(r: ElectionResult): ElectionResultDto {
  const totalSeats = r.lists.reduce((sum, l) => sum + l.seatsCouncil, 0);
  return {
    level: r.level ?? "commune",
    candidates: r.candidates ?? false,
    bureaux: r.bureaux ?? null,
    territoryCode: r.territory.code,
    territoryName: r.territory.name,
    department: r.territory.department,
    registered: r.registered,
    voters: r.voters,
    turnoutPct: r.turnoutPct,
    blank: r.blank,
    nulls: r.nulls,
    expressed: r.expressed,
    lists: r.lists.map(listDto),
    totalSeats,
    majoritySeats: totalSeats > 0 ? majoritySeats(totalSeats) : null,
    complete: r.complete,
    sourceUrl: r.sourceUrl,
  };
}

/** Le résultat d'un territoire, ou rien avant 20 h le jour du scrutin. */
export function toElectionDto(result: ElectionResult, now: Date): ElectionDto | null {
  const election = electionById(result.electionId);
  if (!election) return null;
  const embargo = electionEmbargo(election.date, now);
  return {
    electionId: election.id,
    name: electionLabel(election),
    round: election.round,
    date: election.date,
    embargoed: embargo.embargoed,
    liftsAt: embargo.liftsAt.toISOString(),
    result: embargo.embargoed ? null : toElectionResultDto(result),
  };
}

/** Le résultat de la France entière, parmi les résultats d'un scrutin. */
export function nationalResult(events: { result: unknown }[], now: Date): ElectionResultDto | null {
  for (const e of events) {
    const result = e.result as ElectionResult | null;
    const election = result?.electionId ? electionById(result.electionId) : undefined;
    if (result?.level === "national" && election && !electionEmbargo(election.date, now).embargoed) return toElectionResultDto(result);
  }
  return null;
}

/** Les territoires listés : tout sauf la France entière, qui a sa propre carte. */
export function toElectionTerritories(events: { id: string; result: unknown }[], now: Date): ElectionTerritoryDto[] {
  return events
    .flatMap((e) => {
      const result = e.result as ElectionResult | null;
      const election = result?.electionId ? electionById(result.electionId) : undefined;
      if (!result || !election || result.level === "national" || electionEmbargo(election.date, now).embargoed) return [];
      const leader = result.lists[0];
      return [
        {
          eventId: e.id,
          level: result.level ?? "commune",
          name: result.territory.name,
          department: result.territory.department,
          registered: result.registered,
          turnoutPct: result.turnoutPct,
          leaderLabel: leader?.label ?? null,
          leaderPct: leader?.pctExpressed ?? null,
          complete: result.complete,
        },
      ];
    })
    .sort((a, b) => b.registered - a.registered);
}
