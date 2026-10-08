import { BadRequestException, Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import {
  isQuizChoice,
  parseQuizQuestionId,
  pickQuizQuestions,
  QUIZ_CHOICES,
  quizAnswerOf,
  quizDay,
  quizQuestionId,
  quizStreak,
  QuizVote,
  sortGroupsNeutral,
  VOTE_KIND,
  VoteResult,
} from "@news/domain";
import { IsIn, IsString, MaxLength } from "class-validator";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";
import { outcomeOf, VoteGroupDto, VoteOutcomeDto } from "./politics.dto";

const TTL_SECONDS = 300;

export class QuizQuestionDto {
  /** « <id du vote>:<id du groupe> » */
  @ApiProperty() id!: string;
  @ApiProperty() eventId!: string;
  /** Texte voté. */
  @ApiProperty() lawName!: string;
  @ApiProperty({ nullable: true, type: String }) lawId!: string | null;
  @ApiProperty() date!: string;
  @ApiProperty() groupName!: string;
  @ApiProperty({ nullable: true, type: String }) groupShortName!: string | null;
  /** Les choix proposés, toujours les mêmes et dans le même ordre : pour, contre, abstention. */
  @ApiProperty({ type: [String] }) choices!: string[];
  /** Ma réponse du jour, `null` tant que je n'ai pas répondu. */
  @ApiProperty({ nullable: true, type: String }) myChoice!: string | null;
  @ApiProperty({ nullable: true, type: Boolean }) myCorrect!: boolean | null;
}

export class QuizDto {
  @ApiProperty() day!: string;
  @ApiProperty({ type: [QuizQuestionDto] }) questions!: QuizQuestionDto[];
  /** Vrai avec un compte : les réponses et la série sont gardées. */
  @ApiProperty() signedIn!: boolean;
  @ApiProperty() answered!: number;
  @ApiProperty() correct!: number;
  /** Jours d'affilée avec au moins une réponse (0 sans compte). */
  @ApiProperty() streak!: number;
  @ApiProperty() bestStreak!: number;
}

export class QuizAnswerBodyDto {
  @ApiProperty() @IsString() @MaxLength(120) questionId!: string;
  @ApiProperty({ enum: QUIZ_CHOICES }) @IsIn([...QUIZ_CHOICES]) choice!: string;
}

export class QuizAnswerResultDto {
  @ApiProperty() questionId!: string;
  @ApiProperty() choice!: string;
  @ApiProperty() correct!: boolean;
  /** La bonne réponse : la position de la majorité des voix du groupe. */
  @ApiProperty() answer!: string;
  @ApiProperty({ type: VoteGroupDto }) group!: VoteGroupDto;
  @ApiProperty({ type: VoteOutcomeDto }) vote!: VoteOutcomeDto;
  @ApiProperty() eventId!: string;
  @ApiProperty({ nullable: true, type: String }) lawId!: string | null;
  @ApiProperty() lawName!: string;
  @ApiProperty() date!: string;
  /** Source officielle du scrutin, montrée avec la réponse (docs/01c). */
  @ApiProperty() sourceUrl!: string;
  /** Faux sans compte : la réponse est corrigée mais pas gardée. */
  @ApiProperty() recorded!: boolean;
}

type VoteRow = { id: string; competitionId: string; competition: { name: string }; result: unknown };

// Quiz « Qui a voté ? » (J29b) : le serveur tire les questions du jour et corrige. La bonne réponse ne part qu'avec la
// correction, jamais avec la question. Aucun point (docs/07) : seulement une série de jours.
@Injectable()
export class QuizService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  /** Les cinq questions du jour (id du vote, id du groupe), identiques pour tout le monde. */
  private async todayPicks(day: string): Promise<{ eventId: string; groupId: string }[]> {
    const key = `cache:v1:quiz:${day}`;
    const cached = await this.cache.get<{ eventId: string; groupId: string }[]>(key);
    if (cached) return cached;
    const rows = await this.prisma.event.findMany({ where: { kind: VOTE_KIND }, select: { id: true, result: true } });
    const votes: QuizVote[] = [];
    const names = new Map<string, string>();
    for (const row of rows) {
      const result = row.result as unknown as VoteResult | null;
      if (!result?.groups) continue;
      votes.push({ eventId: row.id, groups: result.groups.map((g) => ({ id: g.id, position: g.position })) });
      for (const g of result.groups) names.set(g.id, g.name);
    }
    const groupIds = sortGroupsNeutral([...names].map(([id, name]) => ({ id, name }))).map((g) => g.id);
    const picks = pickQuizQuestions(votes, groupIds, day);
    await this.cache.set(key, picks, TTL_SECONDS);
    return picks;
  }

  private async votesById(ids: string[]): Promise<Map<string, VoteRow>> {
    const rows = await this.prisma.event.findMany({ where: { id: { in: ids }, kind: VOTE_KIND }, select: { id: true, competitionId: true, competition: { select: { name: true } }, result: true } });
    return new Map(rows.map((r) => [r.id, r]));
  }

  async getQuiz(userId: string | null): Promise<QuizDto> {
    const day = quizDay(new Date());
    const picks = await this.todayPicks(day);
    const votes = await this.votesById(picks.map((p) => p.eventId));
    const mine = userId ? await this.prisma.quizAnswer.findMany({ where: { userId, quizDay: day } }) : [];
    const myAnswers = new Map(mine.map((a) => [a.questionId, a]));
    const history = userId ? await this.prisma.quizAnswer.findMany({ where: { userId }, select: { quizDay: true }, distinct: ["quizDay"] }) : [];
    const streak = quizStreak(history.map((h) => h.quizDay), day);

    const questions = picks.flatMap((pick): QuizQuestionDto[] => {
      const vote = votes.get(pick.eventId);
      const group = (vote?.result as unknown as VoteResult | undefined)?.groups.find((g) => g.id === pick.groupId);
      if (!vote || !group) return [];
      const id = quizQuestionId(pick.eventId, pick.groupId);
      const answer = myAnswers.get(id);
      return [
        {
          id,
          eventId: pick.eventId,
          lawName: vote.competition.name,
          lawId: vote.competitionId,
          date: (vote.result as unknown as VoteResult).date,
          groupName: group.name,
          groupShortName: group.shortName,
          choices: [...QUIZ_CHOICES],
          myChoice: answer?.choice ?? null,
          myCorrect: answer?.correct ?? null,
        },
      ];
    });
    return {
      day,
      questions,
      signedIn: userId !== null,
      answered: mine.length,
      correct: mine.filter((a) => a.correct).length,
      streak: streak.current,
      bestStreak: streak.best,
    };
  }

  async answer(userId: string | null, body: QuizAnswerBodyDto): Promise<QuizAnswerResultDto> {
    const day = quizDay(new Date());
    const parsed = parseQuizQuestionId(body.questionId);
    if (!parsed || !isQuizChoice(body.choice)) throw new BadRequestException("Question ou réponse invalide");
    // Seules les questions du jour : pas de réponses en série à n'importe quel vote.
    if (!(await this.todayPicks(day)).some((p) => p.eventId === parsed.eventId && p.groupId === parsed.groupId)) {
      throw new BadRequestException("Cette question n'est pas au programme du jour");
    }
    const vote = (await this.votesById([parsed.eventId])).get(parsed.eventId);
    const result = vote?.result as unknown as VoteResult | undefined;
    const group = result?.groups.find((g) => g.id === parsed.groupId);
    const answer = group ? quizAnswerOf(group.position) : null;
    if (!vote || !result || !group || !answer) throw new BadRequestException("Question introuvable");

    // Une seule réponse par question : rejouer renvoie la première (on ne peut pas tenter les trois choix).
    let choice = body.choice;
    let recorded = false;
    if (userId) {
      const existing = await this.prisma.quizAnswer.findUnique({ where: { userId_questionId: { userId, questionId: body.questionId } } });
      if (existing) choice = existing.choice as typeof choice;
      else await this.prisma.quizAnswer.create({ data: { userId, quizDay: day, questionId: body.questionId, choice, correct: choice === answer } });
      recorded = true;
    }
    return {
      questionId: body.questionId,
      choice,
      correct: choice === answer,
      answer,
      group,
      vote: outcomeOf(result),
      eventId: vote.id,
      lawId: vote.competitionId,
      lawName: vote.competition.name,
      date: result.date,
      sourceUrl: result.sourceUrl,
      recorded,
    };
  }
}
