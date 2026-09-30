import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { GROUP_CODE_LENGTH, PSEUDO_MAX_LENGTH, PSEUDO_MIN_LENGTH } from "@news/domain";
import { IsInt, IsNotEmpty, IsOptional, IsString, IsUUID, Length, Max, MaxLength, Min } from "class-validator";

export class PutProfileDto {
  @ApiPropertyOptional({ minLength: PSEUDO_MIN_LENGTH, maxLength: PSEUDO_MAX_LENGTH })
  @IsOptional()
  @IsString()
  pseudo?: string;

  @ApiPropertyOptional({ description: "Équipe dont le logo sert d'avatar (une `entity` de type équipe, avec logo)" })
  @IsOptional()
  @IsUUID()
  avatarEntityId?: string;
}

export class PredictionStatsDto {
  @ApiProperty() points!: number;
  @ApiProperty() predictionsCount!: number;
  @ApiProperty({ description: "Pronostics dont le match est terminé" }) settledCount!: number;
  @ApiProperty() correctCount!: number;
  @ApiProperty({ description: "Pronostics justes d'affilée, dans l'ordre des matchs (0 si le dernier était faux)" }) currentStreak!: number;
  @ApiProperty() bestStreak!: number;
}

export class ProfileDto {
  @ApiPropertyOptional({ nullable: true, type: String }) pseudo!: string | null;
  @ApiPropertyOptional({ nullable: true, type: String }) avatarUrl!: string | null;
  @ApiProperty() emailVerified!: boolean;
  @ApiProperty({ description: "Jours à attendre avant de pouvoir changer de pseudo (0 = possible)" }) pseudoChangeWaitDays!: number;
  @ApiProperty({ type: PredictionStatsDto }) stats!: PredictionStatsDto;
}

/** Profil d'un autre joueur, visible seulement par les membres d'un groupe commun. */
export class PublicProfileDto {
  @ApiProperty() userId!: string;
  @ApiProperty() pseudo!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) avatarUrl!: string | null;
  @ApiProperty({ type: PredictionStatsDto }) stats!: PredictionStatsDto;
}

export class PutPredictionDto {
  @ApiProperty() @IsUUID() eventId!: string;
  @ApiProperty() @IsUUID() pickedEntityId!: string;
  @ApiPropertyOptional({ description: "Score de série de l'entité choisie (avec `otherScore`)" })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(10)
  pickedScore?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(10) otherScore?: number;
}

export class PredictionDto {
  @ApiProperty() eventId!: string;
  @ApiProperty() pickedEntityId!: string;
  @ApiPropertyOptional({ nullable: true, type: Number }) pickedScore!: number | null;
  @ApiPropertyOptional({ nullable: true, type: Number }) otherScore!: number | null;
  @ApiPropertyOptional({ nullable: true, type: Number, description: "Nul tant que le match n'est pas terminé (le sans spoil est appliqué par l'appli)" })
  points!: number | null;
}

export class CreateGroupDto {
  @ApiProperty() @IsString() @IsNotEmpty() @MaxLength(40) name!: string;
}

export class JoinGroupDto {
  @ApiProperty({ minLength: GROUP_CODE_LENGTH, maxLength: GROUP_CODE_LENGTH })
  @IsString()
  @Length(GROUP_CODE_LENGTH, GROUP_CODE_LENGTH)
  code!: string;
}

export class GroupDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() code!: string;
  @ApiProperty() memberCount!: number;
  @ApiProperty() isOwner!: boolean;
}

export class GroupRankingEntryDto {
  @ApiProperty() rank!: number;
  @ApiProperty() userId!: string;
  @ApiProperty() pseudo!: string;
  @ApiPropertyOptional({ nullable: true, type: String }) avatarUrl!: string | null;
  @ApiProperty() points!: number;
  @ApiProperty() correctCount!: number;
  @ApiProperty() isMe!: boolean;
}

export class GroupDetailDto extends GroupDto {
  @ApiProperty({ type: [GroupRankingEntryDto] }) ranking!: GroupRankingEntryDto[];
}
