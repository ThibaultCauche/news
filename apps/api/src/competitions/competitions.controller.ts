import { Controller, Get, Param, Query, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { BracketResponseDto, CompetitionResponseDto, CompetitionRootDto, CompetitionsService, RankingResponseDto } from "./competitions.service";

@Controller("competitions")
export class CompetitionsController {
  constructor(private readonly competitions: CompetitionsService) {}

  // GET /v1/competitions/roots?category=esport — écran 09 (filtre "E-sport").
  // Doit rester déclaré avant `:id` : sinon Nest/Express fait correspondre
  // "roots" à ce paramètre en premier.
  @Get("roots")
  @ApiOkResponse({ type: [CompetitionRootDto] })
  async getRoots(@Query("category") category: string): Promise<CompetitionRootDto[]> {
    return this.competitions.getRoots(category);
  }

  // GET /v1/competitions/:id — écrans 01, 06, 14, 19 (docs/03 §4).
  @Get(":id")
  @ApiOkResponse({ type: CompetitionResponseDto })
  async getById(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.competitions.getById(id));
  }

  // GET /v1/competitions/:id/bracket — écrans 02, 05, 07 (docs/03 §4).
  @Get(":id/bracket")
  @ApiOkResponse({ type: BracketResponseDto })
  async getBracket(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.competitions.getBracket(id));
  }

  // GET /v1/competitions/:id/ranking — classement global (J23, #M1).
  @Get(":id/ranking")
  @ApiOkResponse({ type: RankingResponseDto })
  async getRanking(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.competitions.getRanking(id));
  }
}
