import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, UseGuards } from "@nestjs/common";
import { ApiOkResponse, ApiQuery } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { CreateGroupDto, FriendsPicksDto, GroupDetailDto, GroupDto, JoinGroupDto, PredictionDto, ProfileDto, PublicProfileDto, PutPredictionDto, PutProfileDto } from "./community.dto";
import { CommunityService } from "./community.service";
import { PutStagePickDto, StagePickDto, StagePickService } from "./stage-pick.service";

// Profil, pronostics et groupes d'amis (J11, docs/04) : tout exige un compte connecté.
@Controller()
@UseGuards(JwtAuthGuard)
export class CommunityController {
  constructor(
    private readonly community: CommunityService,
    private readonly stagePicks: StagePickService,
  ) {}

  @Get("me/profile")
  @ApiOkResponse({ type: ProfileDto })
  getProfile(@CurrentUser() user: AuthUser): Promise<ProfileDto> {
    return this.community.getProfile(user.id);
  }

  @Put("me/profile")
  @ApiOkResponse({ type: ProfileDto })
  setProfile(@CurrentUser() user: AuthUser, @Body() dto: PutProfileDto): Promise<ProfileDto> {
    return this.community.updateProfile(user.id, dto);
  }

  @Get("users/:id/profile")
  @ApiOkResponse({ type: PublicProfileDto })
  getPublicProfile(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<PublicProfileDto> {
    return this.community.getPublicProfile(user.id, id);
  }

  @Get("predictions")
  @ApiOkResponse({ type: [PredictionDto] })
  listPredictions(@CurrentUser() user: AuthUser): Promise<PredictionDto[]> {
    return this.community.listPredictions(user.id);
  }

  @Put("predictions")
  @ApiOkResponse({ type: PredictionDto })
  putPrediction(@CurrentUser() user: AuthUser, @Body() dto: PutPredictionDto): Promise<PredictionDto> {
    return this.community.putPrediction(user.id, dto);
  }

  // Pronostic d'une phase suisse (J23) : les équipes qu'on pense voir se qualifier, avant le premier match.
  @Get("competitions/:id/pick")
  @ApiOkResponse({ type: StagePickDto })
  getStagePick(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<StagePickDto> {
    return this.stagePicks.get(user.id, id);
  }

  @Put("competitions/:id/pick")
  @ApiOkResponse({ type: StagePickDto })
  putStagePick(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: PutStagePickDto): Promise<StagePickDto> {
    return this.stagePicks.put(user.id, id, dto);
  }

  @Get("events/:id/friends-picks")
  @ApiOkResponse({ type: FriendsPicksDto })
  friendsPicks(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<FriendsPicksDto> {
    return this.community.friendsPicks(user.id, id);
  }

  @Get("groups")
  @ApiOkResponse({ type: [GroupDto] })
  listGroups(@CurrentUser() user: AuthUser): Promise<GroupDto[]> {
    return this.community.listGroups(user.id);
  }

  @Post("groups")
  @ApiOkResponse({ type: GroupDto })
  createGroup(@CurrentUser() user: AuthUser, @Body() dto: CreateGroupDto): Promise<GroupDto> {
    return this.community.createGroup(user.id, dto.name);
  }

  // Limite serrée : le code de 8 caractères ne doit pas pouvoir être deviné par essais répétés.
  @Post("groups/join")
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOkResponse({ type: GroupDto })
  joinGroup(@CurrentUser() user: AuthUser, @Body() dto: JoinGroupDto): Promise<GroupDto> {
    return this.community.joinGroup(user.id, dto.code);
  }

  @Get("groups/:id")
  @ApiOkResponse({ type: GroupDetailDto })
  @ApiQuery({ name: "game", required: false, description: "Slug du jeu : classement limité aux matchs de ce jeu" })
  getGroup(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Query("game") game?: string): Promise<GroupDetailDto> {
    return this.community.getGroup(user.id, id, game);
  }

  @Delete("groups/:id/members/me")
  @HttpCode(204)
  leaveGroup(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.community.leaveGroup(user.id, id);
  }

  @Delete("groups/:id")
  @HttpCode(204)
  deleteGroup(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.community.deleteGroup(user.id, id);
  }
}
