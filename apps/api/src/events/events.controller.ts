import { Controller, Get, Param, Req, Res } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import type { Request, Response } from "express";
import { sendWithEtag } from "../common/etag";
import { EventDetailResponseDto, EventsService } from "./events.service";

// GET /v1/events/:id — écrans 03, 15, 24, 25, 26 (docs/03 §4).
@Controller("events")
export class EventsController {
  constructor(private readonly events: EventsService) {}

  @Get(":id")
  @ApiOkResponse({ type: EventDetailResponseDto })
  async getById(@Param("id") id: string, @Req() req: Request, @Res() res: Response): Promise<void> {
    sendWithEtag(req, res, await this.events.getById(id));
  }
}
