import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { FORUM_MESSAGE_MAX_LENGTH, FORUM_REACTIONS, FORUM_REPORT_REASONS, FORUM_THREAD_KINDS, FORUM_TITLE_MAX_LENGTH } from "@news/domain";
import { Type } from "class-transformer";
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from "class-validator";

export class ForumStatusDto {
  @ApiProperty({ description: "Le forum est ouvert à ce visiteur (bêta fermée : compte autorisé seulement)" }) enabled!: boolean;
  @ApiProperty() signedIn!: boolean;
  @ApiProperty({ description: "Peut écrire maintenant (compte, pseudo, conditions, ancienneté, non exclu)" }) canPost!: boolean;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Pourquoi il ne peut pas écrire : SIGN_IN_REQUIRED, PROFILE_REQUIRED, TERMS_REQUIRED, ACCOUNT_TOO_NEW, BANNED" })
  blockedReason!: string | null;
  @ApiProperty() termsVersion!: number;
  @ApiProperty() termsAccepted!: boolean;
  @ApiProperty() isModerator!: boolean;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Identifiant du compte (pour reconnaître ses propres messages)" }) userId!: string | null;
}

export class AcceptTermsDto {
  @ApiProperty() @IsInt() @Min(1) version!: number;
}

export class ForumThreadDto {
  @ApiProperty() id!: string;
  @ApiProperty({ enum: FORUM_THREAD_KINDS }) kind!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) targetId!: string | null;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Slug du jeu" }) game!: string | null;
  @ApiProperty() title!: string;
  @ApiProperty({ description: "Messages visibles (réponses comprises)" }) messageCount!: number;
  @ApiPropertyOptional({ nullable: true, type: Date }) lastMessageAt!: Date | null;
  @ApiProperty() locked!: boolean;
  @ApiProperty({ description: "Le visiteur suit cette discussion (notifications)" }) following!: boolean;
  @ApiProperty({ description: "Lecture seule : le fil du direct n'accepte de messages que pendant le match" }) readOnly!: boolean;
  @ApiProperty() createdAt!: Date;
}

export class ResolveThreadQueryDto {
  @ApiProperty({ enum: FORUM_THREAD_KINDS }) @IsIn(FORUM_THREAD_KINDS) kind!: string;
  @ApiProperty({ description: "Identifiant du match, de l'équipe, de la compétition, ou slug du jeu" }) @IsString() @MaxLength(100) targetId!: string;
}

export class ListThreadsQueryDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) game?: string;
  @ApiPropertyOptional({ enum: FORUM_THREAD_KINDS }) @IsOptional() @IsIn(FORUM_THREAD_KINDS) kind?: string;
  @ApiPropertyOptional({ enum: ["recent", "active", "popular"], description: "Tri : dernier message (défaut), messages des dernières 24 h, ou messages et réactions" })
  @IsOptional()
  @IsIn(["recent", "active", "popular"])
  sort?: string;
}

export class CreateThreadDto {
  @ApiProperty({ maxLength: FORUM_TITLE_MAX_LENGTH }) @IsString() @MaxLength(200) title!: string;
  @ApiPropertyOptional({ description: "Slug du jeu concerné (badge de camp et filtre)" }) @IsOptional() @IsString() @MaxLength(40) game?: string;
}

export class MessagesQueryDto {
  @ApiPropertyOptional({ description: "Curseur : date de création du plus ancien message déjà reçu" }) @IsOptional() @IsString() before?: string;
  @ApiPropertyOptional({ minimum: 1, maximum: 50 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
}

export class ForumCampBadgeDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) imageUrl!: string | null;
}

export class ForumAuthorDto {
  @ApiProperty() userId!: string;
  @ApiProperty() pseudo!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) avatarUrl!: string | null;
  @ApiPropertyOptional({ nullable: true, type: ForumCampBadgeDto, description: "Camp de l'auteur pour le jeu du fil" }) camp!: ForumCampBadgeDto | null;
}

export class ReactionCountDto {
  @ApiProperty({ enum: FORUM_REACTIONS }) emoji!: string;
  @ApiProperty() count!: number;
}

export class ForumReplyToDto {
  @ApiProperty() messageId!: string;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Nul si le message cité est masqué" }) pseudo!: string | null;
  @ApiProperty({ description: "Extrait du message cité" }) snippet!: string;
}

export class ForumMessageDto {
  @ApiProperty() id!: string;
  @ApiProperty() threadId!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) parentId!: string | null;
  @ApiPropertyOptional({ nullable: true, type: ForumAuthorDto, description: "Nul si le message est masqué" }) author!: ForumAuthorDto | null;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Nul si le message est masqué (signalements, modérateur) ou si l'auteur est bloqué" }) body!: string | null;
  @ApiProperty() hidden!: boolean;
  @ApiPropertyOptional({ nullable: true, type: ForumReplyToDto, description: "Fil du direct (tchat) : message auquel celui-ci répond, sans imbrication" }) replyTo!: ForumReplyToDto | null;
  @ApiProperty({ description: "Modifié après sa publication" }) edited!: boolean;
  @ApiProperty({ description: "Spoiler annoncé par l'auteur : à flouter" }) isSpoiler!: boolean;
  @ApiProperty({ description: "Épinglé en tête de la discussion par un modérateur" }) pinned!: boolean;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: [ReactionCountDto] }) reactions!: ReactionCountDto[];
  @ApiPropertyOptional({ nullable: true, type: String }) myReaction!: string | null;
  @ApiProperty({ type: () => [ForumMessageDto], description: "Réponses directes, de la plus ancienne à la plus récente (arbre imbriqué, profondeur limitée)" }) replies!: ForumMessageDto[];
}

export class ForumMessagesPageDto {
  @ApiProperty({ type: ForumThreadDto }) thread!: ForumThreadDto;
  @ApiProperty({ type: [ForumMessageDto], description: "Messages racines, du plus récent au plus ancien" }) messages!: ForumMessageDto[];
  @ApiPropertyOptional({ nullable: true, type: String, description: "À renvoyer en `before` pour la page suivante, nul s'il n'y en a plus" }) nextBefore!: string | null;
}

export class PostMessageDto {
  @ApiProperty({ maxLength: FORUM_MESSAGE_MAX_LENGTH }) @IsString() @MaxLength(FORUM_MESSAGE_MAX_LENGTH * 2) body!: string;
  @ApiPropertyOptional({ description: "Message annonçant un spoiler (flouté pour tous, révélé par appui)" }) @IsOptional() @IsBoolean() isSpoiler?: boolean;
  @ApiPropertyOptional({ description: "Message auquel on répond (une réponse peut répondre à une réponse, jusqu'à une profondeur limitée)" }) @IsOptional() @IsUUID() parentId?: string;
}

export class EditMessageDto {
  @ApiProperty({ maxLength: FORUM_MESSAGE_MAX_LENGTH }) @IsString() @MaxLength(FORUM_MESSAGE_MAX_LENGTH * 2) body!: string;
}

export class PutReactionDto {
  @ApiProperty({ enum: FORUM_REACTIONS }) @IsIn(FORUM_REACTIONS) emoji!: string;
}

export class ReportMessageDto {
  @ApiProperty({ enum: FORUM_REPORT_REASONS }) @IsIn(FORUM_REPORT_REASONS) reason!: string;
}

export class BlockedUserDto {
  @ApiProperty() userId!: string;
  @ApiProperty() pseudo!: string;
}

export class ForumCampDto {
  @ApiProperty() game!: string;
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty({ description: "Jours à attendre avant de pouvoir changer de camp (0 = possible)" }) changeWaitDays!: number;
}

export class PutCampDto {
  @ApiProperty() @IsString() @MaxLength(40) game!: string;
  @ApiProperty() @IsUUID() entityId!: string;
}

export class ReportedMessageDto {
  @ApiProperty() messageId!: string;
  @ApiProperty() threadId!: string;
  @ApiProperty() threadTitle!: string;
  @ApiProperty() authorId!: string;
  @ApiProperty() authorPseudo!: string;
  @ApiProperty() body!: string;
  @ApiProperty() hidden!: boolean;
  @ApiProperty() reportCount!: number;
  @ApiProperty({ type: [String] }) reasons!: string[];
  @ApiProperty() createdAt!: Date;
}

export class ModerationLogDto {
  @ApiProperty() id!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) moderatorPseudo!: string | null;
  @ApiProperty({ description: "hide, dismiss, ban, unban, lock, unlock, pin, unpin" }) action!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) targetPseudo!: string | null;
  @ApiPropertyOptional({ nullable: true, type: String, description: "Extrait du message concerné" }) detail!: string | null;
  @ApiProperty() createdAt!: Date;
}
