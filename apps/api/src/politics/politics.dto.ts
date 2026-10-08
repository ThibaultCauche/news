import { ApiProperty } from "@nestjs/swagger";
import { LawStructure, VoteResult, voteSentence } from "@news/domain";
import { ElectionCardDto } from "./elections.dto";

// Politique (J29) : suivi d'une loi « façon colis » et résultat d'un vote par groupe. Toutes les valeurs viennent de
// l'open data de l'Assemblée ; aucune phrase n'est écrite librement (règle 9 de CLAUDE.md).

export class VoteOutcomeDto {
  @ApiProperty({ enum: ["adopté", "rejeté"] }) sort!: string;
  @ApiProperty() pour!: number;
  @ApiProperty() contre!: number;
  @ApiProperty() abst!: number;
  /** « Adopté : 312 pour, 198 contre, 41 abstentions » (gabarit fixe). */
  @ApiProperty() sentence!: string;
}

export class VoteGroupDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty() members!: number;
  @ApiProperty() pour!: number;
  @ApiProperty() contre!: number;
  @ApiProperty() abst!: number;
  @ApiProperty() nonVotants!: number;
  @ApiProperty({ enum: ["pour", "contre", "abstention", "non-votant"] }) position!: string;
}

export class ScrutinDto extends VoteOutcomeDto {
  @ApiProperty() numero!: number;
  @ApiProperty() date!: string;
  @ApiProperty() announcement!: string;
  @ApiProperty({ nullable: true, type: String }) voteType!: string | null;
  @ApiProperty() nonVotants!: number;
  @ApiProperty() votants!: number;
  /** Nombre de voix requis pour adopter le texte. */
  @ApiProperty() majority!: number;
  @ApiProperty({ type: [VoteGroupDto] }) groups!: VoteGroupDto[];
  @ApiProperty() sourceUrl!: string;
  /** Texte voté, pour revenir à son suivi. */
  @ApiProperty({ nullable: true, type: String }) lawId!: string | null;
  @ApiProperty({ nullable: true, type: String }) lawName!: string | null;
}

export class LawVoteDto extends VoteOutcomeDto {
  /** Événement du vote, `null` si on ne l'a pas retrouvé. */
  @ApiProperty({ nullable: true, type: String }) eventId!: string | null;
  @ApiProperty() numero!: number;
}

export class LawStepDto {
  @ApiProperty() key!: string;
  @ApiProperty() label!: string;
  @ApiProperty({ enum: ["done", "current", "todo", "skipped"] }) state!: string;
  @ApiProperty({ nullable: true, type: String }) date!: string | null;
  @ApiProperty({ nullable: true, type: String }) detail!: string | null;
  @ApiProperty({ nullable: true, type: LawVoteDto }) vote!: LawVoteDto | null;
}

export class LawAuthorDto {
  @ApiProperty({ enum: ["government", "deputy", "senators"] }) kind!: string;
  @ApiProperty({ nullable: true, type: String }) name!: string | null;
  @ApiProperty({ nullable: true, type: String }) group!: string | null;
  @ApiProperty() cosigners!: number;
}

export class LawDto {
  @ApiProperty({ enum: ["in_progress", "promulgated", "rejected"] }) status!: string;
  @ApiProperty() officialTitle!: string;
  /** « Proposition de loi organique ». */
  @ApiProperty() lawType!: string;
  @ApiProperty({ nullable: true, type: LawAuthorDto }) author!: LawAuthorDto | null;
  @ApiProperty({ nullable: true, type: String }) lawNumber!: string | null;
  @ApiProperty({ nullable: true, type: String }) legifranceUrl!: string | null;
  @ApiProperty() sourceUrl!: string;
  @ApiProperty({ type: [LawStepDto] }) steps!: LawStepDto[];
}

// Une loi dans une liste (page Politique).
export class LawCardDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() lawType!: string;
  @ApiProperty({ enum: ["in_progress", "promulgated", "rejected"] }) status!: string;
  /** Étape « en ce moment », ou la dernière étape faite pour un texte terminé. */
  @ApiProperty({ nullable: true, type: String }) stepLabel!: string | null;
  /** Date du dernier acte connu. */
  @ApiProperty({ nullable: true, type: String }) lastDate!: string | null;
}

export class VoteCardDto {
  @ApiProperty() eventId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() date!: string;
  @ApiProperty({ type: VoteOutcomeDto }) outcome!: VoteOutcomeDto;
  @ApiProperty({ nullable: true, type: String }) lawId!: string | null;
  /** Titre du texte voté (plus court que le titre du scrutin). */
  @ApiProperty({ nullable: true, type: String }) lawName!: string | null;
}

export class PoliticsOverviewDto {
  @ApiProperty({ type: [VoteCardDto] }) votes!: VoteCardDto[];
  @ApiProperty({ type: [LawCardDto] }) inProgress!: LawCardDto[];
  @ApiProperty({ type: [LawCardDto] }) promulgated!: LawCardDto[];
  /** Prochain scrutin d'abord, puis les derniers. */
  @ApiProperty({ type: [ElectionCardDto] }) elections!: ElectionCardDto[];
  @ApiProperty() sourceUpdatedAt!: string;
}

export const outcomeOf = (r: Pick<VoteResult, "sort" | "pour" | "contre" | "abst">): VoteOutcomeDto => ({
  sort: r.sort,
  pour: r.pour,
  contre: r.contre,
  abst: r.abst,
  sentence: voteSentence(r),
});

export function toVoteDto(result: VoteResult, law: { id: string; name: string } | null): ScrutinDto {
  return {
    ...outcomeOf(result),
    numero: result.numero,
    date: result.date,
    announcement: result.announcement,
    voteType: result.voteType,
    nonVotants: result.nonVotants,
    votants: result.votants,
    majority: result.required,
    groups: result.groups,
    sourceUrl: result.sourceUrl,
    lawId: law?.id ?? null,
    lawName: law?.name ?? null,
  };
}

// `voteEventIds` : numéro de scrutin → événement, pour que chaque étape de vote ouvre son écran.
export function toLawDto(structure: LawStructure, voteEventIds: Map<number, string>): LawDto {
  return {
    status: structure.process.status,
    officialTitle: structure.officialTitle,
    lawType: structure.lawType,
    author: structure.author,
    lawNumber: structure.lawNumber,
    legifranceUrl: structure.legifranceUrl,
    sourceUrl: structure.sourceUrl,
    steps: structure.process.steps.map((s) => ({
      key: s.key,
      label: s.label,
      state: s.state,
      date: s.date,
      detail: s.detail,
      vote: s.vote ? { ...outcomeOf(s.vote), eventId: voteEventIds.get(s.vote.numero) ?? null, numero: s.vote.numero } : null,
    })),
  };
}
