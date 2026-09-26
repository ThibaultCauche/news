import { Body, Controller, Delete, Get, HttpCode, Patch, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { MeService } from "./me.service";
import { UpdateUserSettingDto, UserSettingDto } from "./user-setting.dto";

// GET/PATCH /v1/me/settings (écran 22 Réglages), DELETE /v1/me (RGPD) — docs/03 §4/§9.
@Controller("me")
@UseGuards(JwtAuthGuard)
export class MeController {
  constructor(private readonly me: MeService) {}

  @Get("settings")
  @ApiOkResponse({ type: UserSettingDto })
  async getSettings(@CurrentUser() user: AuthUser): Promise<UserSettingDto> {
    return this.me.getSettings(user.id);
  }

  @Patch("settings")
  @ApiOkResponse({ type: UserSettingDto })
  async updateSettings(@CurrentUser() user: AuthUser, @Body() dto: UpdateUserSettingDto): Promise<UserSettingDto> {
    return this.me.updateSettings(user.id, dto);
  }

  @Delete()
  @HttpCode(204)
  async deleteAccount(@CurrentUser() user: AuthUser): Promise<void> {
    await this.me.deleteAccount(user.id);
  }
}
