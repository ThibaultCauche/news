import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Put, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { LearnProgressDto, LearnProgressEntryDto, PutLearnProgressDto } from "./learn.dto";
import { LearnService } from "./learn.service";
import { MeService } from "./me.service";
import { UpdateUserSettingDto, UserSettingDto } from "./user-setting.dto";

// GET/PATCH /v1/me/settings (écran 22 Réglages), DELETE /v1/me (RGPD) — docs/03 §4/§9.
@Controller("me")
@UseGuards(JwtAuthGuard)
export class MeController {
  constructor(
    private readonly me: MeService,
    private readonly learn: LearnService,
  ) {}

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

  // Progression dans les tutos (J12) : écran Profil.
  @Get("learn")
  @ApiOkResponse({ type: LearnProgressDto })
  async getLearn(@CurrentUser() user: AuthUser): Promise<LearnProgressDto> {
    return this.learn.get(user.id);
  }

  @Put("learn/:guide/:articleId")
  @ApiOkResponse({ type: LearnProgressEntryDto })
  async putLearn(
    @CurrentUser() user: AuthUser,
    @Param("guide") guide: string,
    @Param("articleId") articleId: string,
    @Body() dto: PutLearnProgressDto,
  ): Promise<LearnProgressEntryDto> {
    return this.learn.put(user.id, guide, articleId, dto.quizPassed);
  }

  @Delete()
  @HttpCode(204)
  async deleteAccount(@CurrentUser() user: AuthUser): Promise<void> {
    await this.me.deleteAccount(user.id);
  }
}
