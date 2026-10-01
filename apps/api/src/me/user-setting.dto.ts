import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsBoolean, IsInt, IsOptional, Max, Min } from "class-validator";

export class UserSettingDto {
  @ApiProperty() spoilerFree!: boolean;
  // Réglage seul (J6) : l'envoi réel du résumé du matin n'est pas encore construit
  // (pas de contenu "l'essentiel en 3 points" à générer).
  @ApiProperty() morningDigest!: boolean;
  @ApiProperty({ nullable: true, type: Number }) quietHoursStart!: number | null;
  @ApiProperty({ nullable: true, type: Number }) quietHoursEnd!: number | null;
  // Forum (J13) : notification quand on répond à un de ses messages.
  @ApiProperty() notifyForumReplies!: boolean;
  @ApiProperty() notifyForumThreads!: boolean;
  // J14 : réglage global par type de notification (en plus des options de chaque suivi).
  @ApiProperty() notifyMatchReminder!: boolean;
  @ApiProperty() notifyMatchStart!: boolean;
  @ApiProperty() notifyMatchResult!: boolean;
  @ApiProperty() notifyQualification!: boolean;
  @ApiProperty() notifyPredictionReminders!: boolean;
}

// `null` explicite pour effacer des heures calmes déjà réglées : `undefined` (champ
// absent) laisse la valeur actuelle inchangée, `null` la remet à "pas d'heures calmes".
export class UpdateUserSettingDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  spoilerFree?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  morningDigest?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyForumReplies?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyForumThreads?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyMatchReminder?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyMatchStart?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyMatchResult?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyQualification?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyPredictionReminders?: boolean;

  @ApiPropertyOptional({ nullable: true, type: Number })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(23)
  quietHoursStart?: number | null;

  @ApiPropertyOptional({ nullable: true, type: Number })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(23)
  quietHoursEnd?: number | null;
}
