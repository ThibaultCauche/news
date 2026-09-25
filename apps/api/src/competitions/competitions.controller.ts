import { Controller, Get, Param, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { CompetitionResponseDto, CompetitionsService } from "./competitions.service";

// GET /v1/competitions/:id — écrans 01, 06, 14, 19 (docs/03 §4).
@Controller("competitions")
export class CompetitionsController {
  constructor(private readonly competitions: CompetitionsService) {}

  @Get(":id")
  @ApiOkResponse({ type: CompetitionResponseDto })
  async getById(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.competitions.getById(id));
  }
}
