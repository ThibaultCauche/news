import { Body, Controller, Get, HttpCode, Post, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { OptionalUserGuard } from "../auth/jwt-auth.guard";
import { PoliticsOverviewDto } from "./politics.dto";
import { PoliticsService } from "./politics.service";
import { QuizAnswerBodyDto, QuizAnswerResultDto, QuizDto, QuizService } from "./quiz.service";

// GET /v1/politics — page Politique (J29) ; quiz « Qui a voté ? » (J29b), jouable sans compte (rien n'est gardé alors).
@Controller("politics")
export class PoliticsController {
  constructor(
    private readonly politics: PoliticsService,
    private readonly quiz: QuizService,
  ) {}

  @Get()
  @ApiOkResponse({ type: PoliticsOverviewDto })
  async get(): Promise<PoliticsOverviewDto> {
    return this.politics.getOverview();
  }

  @Get("quiz")
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: QuizDto })
  getQuiz(@CurrentUser() user: AuthUser | null): Promise<QuizDto> {
    return this.quiz.getQuiz(user?.id ?? null);
  }

  @Post("quiz/answer")
  @HttpCode(200)
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: QuizAnswerResultDto })
  answer(@CurrentUser() user: AuthUser | null, @Body() body: QuizAnswerBodyDto): Promise<QuizAnswerResultDto> {
    return this.quiz.answer(user?.id ?? null, body);
  }
}
