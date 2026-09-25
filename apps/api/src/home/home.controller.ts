import { Controller, Get, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { HomeResponseDto, HomeService } from "./home.service";

// GET /v1/home — écran 17 Accueil (docs/03 §4).
@Controller("home")
export class HomeController {
  constructor(private readonly home: HomeService) {}

  @Get()
  @ApiOkResponse({ type: HomeResponseDto })
  async getHome(@Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.home.getHome());
  }
}
