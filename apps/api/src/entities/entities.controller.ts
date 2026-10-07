import { Controller, Get, Param, Query, Req, Res } from "@nestjs/common";
import { ApiOkResponse, ApiQuery } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { EntitiesService, EntityListItemDto, EntityPoolDto, EntityResponseDto } from "./entities.service";

// GET /v1/entities/:id — écran 10 Fiche équipe (docs/03 §4).
@Controller("entities")
export class EntitiesController {
  constructor(private readonly entities: EntitiesService) {}

  // GET /v1/entities?game=valorant — onglet Équipes d'un jeu (J9).
  @Get()
  @ApiOkResponse({ type: [EntityListItemDto] })
  async listByGame(@Query("game") game: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.listByGame(game));
  }

  // Avant `:id` : sinon Nest matcherait "by-short-name" comme un `id`.
  @Get("by-short-name/:shortName")
  @ApiQuery({ name: "game", required: false, type: String, description: "Slug du jeu, pour départager deux équipes de même nom court" })
  @ApiOkResponse({ type: EntityResponseDto })
  async getByShortName(@Param("shortName") shortName: string, @Query("game") game: string | undefined, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.getByShortName(shortName, game));
  }

  // GET /v1/entities/:id/pool — la poule d'un joueur (J27).
  @Get(":id/pool")
  @ApiOkResponse({ type: EntityPoolDto })
  async pool(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.poolOf(id));
  }

  @Get(":id")
  @ApiOkResponse({ type: EntityResponseDto })
  async getById(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.entities.getById(id));
  }
}
