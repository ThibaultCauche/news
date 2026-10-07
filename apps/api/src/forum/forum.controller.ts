import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, Query, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard, OptionalUserGuard } from "../auth/jwt-auth.guard";
import {
  AcceptTermsDto,
  CreateDmDto,
  ForumContactDto,
  ForumSearchResultDto,
  InboxItemDto,
  SearchQueryDto,
  SetIdeaStatusDto,
  VoteDto,
  BlockedUserDto,
  CreateThreadDto,
  EditMessageDto,
  ForumCampDto,
  ForumMessageDto,
  ForumMessagesPageDto,
  ForumStatusDto,
  ForumThreadDto,
  ListThreadsQueryDto,
  MessagesQueryDto,
  ModerationLogDto,
  PostMessageDto,
  PutCampDto,
  PutReactionDto,
  ReportedMessageDto,
  ReportMessageDto,
  ResolveThreadQueryDto,
} from "./forum.dto";
import { ForumService } from "./forum.service";
import { InboxService } from "./inbox.service";
import { ModerationService } from "./moderation.service";

// Forum (J13) : lecture ouverte aux invités (quand le forum est ouvert), le reste exige un compte.
@Controller("forum")
export class ForumController {
  constructor(
    private readonly forum: ForumService,
    private readonly inbox: InboxService,
  ) {}

  // ---- Discussion (J24) : boîte, messages privés, fil de groupe, recherche ----

  @Get("inbox")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [InboxItemDto] })
  getInbox(@CurrentUser() user: AuthUser): Promise<InboxItemDto[]> {
    return this.inbox.inbox(user.id);
  }

  @Get("contacts")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [ForumContactDto] })
  contacts(@CurrentUser() user: AuthUser): Promise<ForumContactDto[]> {
    return this.inbox.contacts(user.id);
  }

  @Post("dm")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumThreadDto })
  openDm(@CurrentUser() user: AuthUser, @Body() dto: CreateDmDto): Promise<ForumThreadDto> {
    return this.inbox.openDm(user.id, dto.userId);
  }

  @Get("groups/:id/thread")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumThreadDto })
  groupThread(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<ForumThreadDto> {
    return this.inbox.groupThread(user.id, id);
  }

  @Get("search")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [ForumSearchResultDto] })
  search(@CurrentUser() user: AuthUser, @Query() q: SearchQueryDto): Promise<ForumSearchResultDto[]> {
    return this.inbox.search(user.id, q.q);
  }

  @Get("status")
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: ForumStatusDto })
  status(@CurrentUser() user: AuthUser | null): Promise<ForumStatusDto> {
    return this.forum.getStatus(user?.id ?? null);
  }

  @Post("terms")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumStatusDto })
  acceptTerms(@CurrentUser() user: AuthUser, @Body() dto: AcceptTermsDto): Promise<ForumStatusDto> {
    return this.forum.acceptTerms(user.id, dto.version);
  }

  @Get("threads")
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: [ForumThreadDto] })
  listThreads(@CurrentUser() user: AuthUser | null, @Query() q: ListThreadsQueryDto): Promise<ForumThreadDto[]> {
    return this.forum.listThreads(user?.id ?? null, q);
  }

  // Fil d'un match, d'une équipe, d'une compétition ou d'un jeu : créé automatiquement à la première demande.
  @Get("threads/resolve")
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: ForumThreadDto })
  resolveThread(@CurrentUser() user: AuthUser | null, @Query() q: ResolveThreadQueryDto): Promise<ForumThreadDto> {
    return this.forum.resolveThread(user?.id ?? null, q);
  }

  @Post("threads")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumThreadDto })
  createThread(@CurrentUser() user: AuthUser, @Body() dto: CreateThreadDto): Promise<ForumThreadDto> {
    return this.forum.createThread(user.id, dto);
  }

  @Get("threads/:id/messages")
  @UseGuards(OptionalUserGuard)
  @ApiOkResponse({ type: ForumMessagesPageDto })
  listMessages(@CurrentUser() user: AuthUser | null, @Param("id", ParseUUIDPipe) id: string, @Query() q: MessagesQueryDto): Promise<ForumMessagesPageDto> {
    return this.forum.listMessages(user?.id ?? null, id, q);
  }

  @Post("threads/:id/messages")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumMessageDto })
  postMessage(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: PostMessageDto): Promise<ForumMessageDto> {
    return this.forum.postMessage(user.id, id, dto);
  }

  @Put("threads/:id/follow")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  follow(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.followThread(user.id, id);
  }

  @Delete("threads/:id/follow")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  unfollow(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.unfollowThread(user.id, id);
  }

  @Patch("messages/:id")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: ForumMessageDto })
  editMessage(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: EditMessageDto): Promise<ForumMessageDto> {
    return this.forum.editMessage(user.id, id, dto.body);
  }

  @Delete("messages/:id")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  deleteMessage(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.deleteMessage(user.id, id);
  }

  @Put("messages/:id/reaction")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  putReaction(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: PutReactionDto): Promise<void> {
    return this.forum.putReaction(user.id, id, dto.emoji);
  }

  @Delete("messages/:id/reaction")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  deleteReaction(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.deleteReaction(user.id, id);
  }

  @Post("messages/:id/report")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  report(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: ReportMessageDto): Promise<void> {
    return this.forum.reportMessage(user.id, id, dto);
  }

  @Put("threads/:id/mute")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  mute(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.setMuted(user.id, id, true);
  }

  @Delete("threads/:id/mute")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  unmute(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.setMuted(user.id, id, false);
  }

  @Put("threads/:id/typing")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  typing(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.putTyping(user.id, id);
  }

  @Put("messages/:id/vote")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  putVote(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: VoteDto): Promise<void> {
    return this.forum.putVote(user.id, id, dto.option);
  }

  @Delete("messages/:id/vote")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  deleteVote(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.forum.deleteVote(user.id, id);
  }

  @Get("blocks")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [BlockedUserDto] })
  listBlocks(@CurrentUser() user: AuthUser): Promise<BlockedUserDto[]> {
    return this.forum.listBlocks(user.id);
  }

  @Put("blocks/:userId")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  block(@CurrentUser() user: AuthUser, @Param("userId", ParseUUIDPipe) userId: string): Promise<void> {
    return this.forum.block(user.id, userId);
  }

  @Delete("blocks/:userId")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  unblock(@CurrentUser() user: AuthUser, @Param("userId", ParseUUIDPipe) userId: string): Promise<void> {
    return this.forum.unblock(user.id, userId);
  }

  @Get("camps")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [ForumCampDto] })
  listCamps(@CurrentUser() user: AuthUser): Promise<ForumCampDto[]> {
    return this.forum.listCamps(user.id);
  }

  @Put("camps")
  @UseGuards(JwtAuthGuard)
  @ApiOkResponse({ type: [ForumCampDto] })
  putCamp(@CurrentUser() user: AuthUser, @Body() dto: PutCampDto): Promise<ForumCampDto[]> {
    return this.forum.putCamp(user.id, dto);
  }

  @Delete("camps/:game")
  @UseGuards(JwtAuthGuard)
  @HttpCode(204)
  deleteCamp(@CurrentUser() user: AuthUser, @Param("game") game: string): Promise<void> {
    return this.forum.deleteCamp(user.id, game);
  }
}

// Modération : réservée aux comptes `is_moderator`.
@Controller("forum/moderation")
@UseGuards(JwtAuthGuard)
export class ModerationController {
  constructor(private readonly moderation: ModerationService) {}

  @Get("reports")
  @ApiOkResponse({ type: [ReportedMessageDto] })
  reports(@CurrentUser() user: AuthUser): Promise<ReportedMessageDto[]> {
    return this.moderation.listReports(user.id);
  }

  @Get("log")
  @ApiOkResponse({ type: [ModerationLogDto] })
  log(@CurrentUser() user: AuthUser): Promise<ModerationLogDto[]> {
    return this.moderation.listLog(user.id);
  }

  @Put("messages/:id/pin")
  @HttpCode(204)
  pin(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.setPin(user.id, id, true);
  }

  @Delete("messages/:id/pin")
  @HttpCode(204)
  unpin(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.setPin(user.id, id, false);
  }

  @Post("messages/:id/dismiss")
  @HttpCode(204)
  dismiss(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.dismiss(user.id, id);
  }

  @Post("messages/:id/hide")
  @HttpCode(204)
  hide(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.hide(user.id, id);
  }

  @Put("users/:userId/ban")
  @HttpCode(204)
  ban(@CurrentUser() user: AuthUser, @Param("userId", ParseUUIDPipe) userId: string): Promise<void> {
    return this.moderation.setBan(user.id, userId, true);
  }

  @Delete("users/:userId/ban")
  @HttpCode(204)
  unban(@CurrentUser() user: AuthUser, @Param("userId", ParseUUIDPipe) userId: string): Promise<void> {
    return this.moderation.setBan(user.id, userId, false);
  }

  @Put("messages/:id/idea-status")
  @HttpCode(204)
  setIdeaStatus(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string, @Body() dto: SetIdeaStatusDto): Promise<void> {
    return this.moderation.setIdeaStatus(user.id, id, dto.status);
  }

  @Delete("messages/:id/idea-status")
  @HttpCode(204)
  clearIdeaStatus(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.setIdeaStatus(user.id, id, null);
  }

  @Put("threads/:id/lock")
  @HttpCode(204)
  lock(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.setLock(user.id, id, true);
  }

  @Delete("threads/:id/lock")
  @HttpCode(204)
  unlock(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    return this.moderation.setLock(user.id, id, false);
  }
}
