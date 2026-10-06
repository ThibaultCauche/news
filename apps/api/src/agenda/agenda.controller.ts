import { Controller, Get, Query, Req, Res, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { OptionalUserGuard } from "../auth/jwt-auth.guard";
import { sendWithEtag } from "../common/etag";
import { AgendaQueryDto } from "./agenda.query.dto";
import { AgendaResponseDto, AgendaService } from "./agenda.service";

// GET /v1/agenda — écran 09 Agenda unifié (docs/03 §4).
@Controller("agenda")
export class AgendaController {
  constructor(private readonly agenda: AgendaService) {}

  @Get()
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: AgendaResponseDto })
  async getAgenda(@Query() query: AgendaQueryDto, @CurrentUser() user: AuthUser | null, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.agenda.getAgenda(query, user?.id ?? null));
  }
}
