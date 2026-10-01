import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { IsBoolean, IsOptional } from "class-validator";

export class LearnProgressEntryDto {
  @ApiProperty({ description: "Fichier de tutos : `valorant`, `app`…" }) guide!: string;
  @ApiProperty() articleId!: string;
  @ApiProperty() quizPassed!: boolean;
}

export class LearnProgressDto {
  @ApiProperty({ type: [LearnProgressEntryDto], description: "Les tutos ouverts ; `quizPassed` dit si le quiz est réussi" })
  entries!: LearnProgressEntryDto[];
}

export class PutLearnProgressDto {
  @ApiPropertyOptional({ description: "`true` quand le quiz est réussi ; une valeur réussie n'est jamais retirée" })
  @IsOptional()
  @IsBoolean()
  quizPassed?: boolean;
}
