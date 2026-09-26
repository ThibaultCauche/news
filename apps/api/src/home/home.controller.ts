import { Controller, Get, Req, Res, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Response } from "express";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { OptionalUserGuard, RequestWithUser } from "../auth/jwt-auth.guard";
import { sendWithEtag } from "../common/etag";
import { HomeResponseDto, HomeService } from "./home.service";

// GET /v1/home — écran 17 Accueil (docs/03 §4). Personnalisé si un jeton valide
// est fourni, sinon la version sans compte du J2 (docs/04 J4).
@Controller("home")
export class HomeController {
  constructor(private readonly home: HomeService) {}

  @Get()
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: HomeResponseDto })
  async getHome(@CurrentUser() user: AuthUser | null, @Req() req: RequestWithUser, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.home.getHome(user?.id ?? null));
  }
}
