import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsDateString, IsOptional, IsString } from "class-validator";

// GET /v1/agenda?from&to&category (docs/03 §4). `from`/`to` en ISO 8601.
export class AgendaQueryDto {
  @ApiProperty()
  @IsDateString()
  from!: string;

  @ApiProperty()
  @IsDateString()
  to!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  category?: string;

  // Écran 09 : choix des compétitions racines (un jeu = une ligue racine,
  // ex. "VCT" pour Valorant) dans le pill "E-sport", séparées par une
  // virgule. Absent ou vide = pas de restriction (tous les jeux).
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  leagueIds?: string;
}
