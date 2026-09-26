import { Body, Controller, Delete, Get, HttpCode, Post, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { CurrentUser } from "../auth/current-user.decorator";
import { AuthUser } from "../auth/auth.types";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { CreateSubscriptionDto, FollowStateDto, SubscriptionDto, SubscriptionTargetDto } from "./subscription.dto";
import { SubscriptionsService } from "./subscriptions.service";

// POST/DELETE /v1/subscriptions (docs/03 §4, bouton "Suivre" partout) ; GET
// /v1/subscriptions pour l'écran Suivis (docs/02), pas dans la liste d'endpoints
// documentée mais nécessaire pour l'afficher sans dépendre du contenu de `/v1/home`.
@Controller("subscriptions")
@UseGuards(JwtAuthGuard)
export class SubscriptionsController {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  @Get()
  @ApiOkResponse({ type: [FollowStateDto] })
  async list(@CurrentUser() user: AuthUser): Promise<FollowStateDto[]> {
    return this.subscriptions.listWithState(user.id);
  }

  @Post()
  @ApiOkResponse({ type: SubscriptionDto })
  async create(@CurrentUser() user: AuthUser, @Body() dto: CreateSubscriptionDto): Promise<SubscriptionDto> {
    return this.subscriptions.create(user.id, dto);
  }

  @Delete()
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthUser, @Body() dto: SubscriptionTargetDto): Promise<void> {
    await this.subscriptions.remove(user.id, dto);
  }
}
