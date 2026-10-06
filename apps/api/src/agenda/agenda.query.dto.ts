import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsDateString, IsIn, IsOptional, IsString } from "class-validator";

// GET /v1/agenda?from&to&category (docs/03 §4). `from`/`to` en ISO 8601.
export class AgendaQueryDto {
  @ApiProperty()
  @IsDateString()
  from!: string;

  @ApiProperty()
  @IsDateString()
  to!: string;

  // Une ou plusieurs catégories séparées par une virgule (« esport,sport »).
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

  // « Mes suivis » (J22, #D1) : seulement les matchs couverts par les suivis du compte.
  @ApiPropertyOptional({ enum: ["true", "false"] })
  @IsOptional()
  @IsIn(["true", "false"])
  mine?: string;
}
