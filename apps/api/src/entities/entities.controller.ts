import { Controller, Get, Param, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { EntitiesService, EntityResponseDto } from "./entities.service";

// GET /v1/entities/:id — écran 10 Fiche équipe (docs/03 §4).
@Controller("entities")
export class EntitiesController {
  constructor(private readonly entities: EntitiesService) {}

  // Avant `:id` : sinon Nest matcherait "by-short-name" comme un `id`.
  @Get("by-short-name/:shortName")
  @ApiOkResponse({ type: EntityResponseDto })
  async getByShortName(@Param("shortName") shortName: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.getByShortName(shortName));
  }

  @Get(":id")
  @ApiOkResponse({ type: EntityResponseDto })
  async getById(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.getById(id));
  }
}
