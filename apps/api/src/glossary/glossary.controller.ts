import { Controller, Get, Param, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { GlossaryService, GlossaryTermDto } from "./glossary.service";

// GET /v1/glossary/:term — écran 04 Feuille glossaire (docs/03 §4).
@Controller("glossary")
export class GlossaryController {
  constructor(private readonly glossary: GlossaryService) {}

  @Get(":term")
  @ApiOkResponse({ type: GlossaryTermDto })
  async getByTerm(@Param("term") term: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.glossary.getByTerm(term));
  }
}
