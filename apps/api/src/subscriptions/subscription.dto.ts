import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { SUBSCRIPTION_LEVELS, SUBSCRIPTION_TARGET_TYPES, SubscriptionLevel, SubscriptionTargetType } from "@news/domain";
import { IsBoolean, IsIn, IsOptional, IsUUID } from "class-validator";
import { EventSummaryDto } from "../common/event-summary.mapper";

// Body partagé par `POST` et `DELETE /v1/subscriptions` : une entité/compétition/
// catégorie/événement identifie la cible (docs/03 §2 §4).
export class SubscriptionTargetDto {
  @ApiProperty({ enum: SUBSCRIPTION_TARGET_TYPES })
  @IsIn(SUBSCRIPTION_TARGET_TYPES)
  targetType!: SubscriptionTargetType;

  @ApiProperty()
  @IsUUID()
  targetId!: string;
}

export class CreateSubscriptionDto extends SubscriptionTargetDto {
  @ApiPropertyOptional({ enum: SUBSCRIPTION_LEVELS })
  @IsOptional()
  @IsIn(SUBSCRIPTION_LEVELS)
  level?: SubscriptionLevel;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyReminder?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyStart?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  notifyResult?: boolean;
}

export class SubscriptionDto {
  @ApiProperty() id!: string;
  @ApiProperty() targetType!: string;
  @ApiProperty() targetId!: string;
  @ApiProperty() level!: string;
  @ApiProperty() notifyReminder!: boolean;
  @ApiProperty() notifyStart!: boolean;
  @ApiProperty() notifyResult!: boolean;
}

// Écran Suivis (docs/02) : chaque suivi avec son état en une ligne — l'événement
// le plus pertinent (en direct, sinon le plus proche à venir), ou `null` si rien
// n'est prévu.
export class FollowStateDto extends SubscriptionDto {
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: EventSummaryDto }) currentEvent!: EventSummaryDto | null;
  // Logo et statut de compétition : seulement pour un suivi d'équipe
  // (`targetType: "entity"`), `null` sinon (docs/04 J8).
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty({ nullable: true, type: String, enum: ["qualified", "eliminated"] }) status!: "qualified" | "eliminated" | null;
}
