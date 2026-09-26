import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { DEVICE_PLATFORMS, DevicePlatform } from "@news/domain";
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from "class-validator";

// `installId` : identifiant généré une fois côté appli (persisté localement), pas
// le jeton push lui-même — il peut manquer tant que la permission n'est pas
// accordée, et change quand FCM le fait tourner (docs/04 J4).
export class PutDeviceDto {
  @ApiProperty()
  @IsString()
  installId!: string;

  @ApiProperty({ enum: DEVICE_PLATFORMS })
  @IsIn(DEVICE_PLATFORMS)
  platform!: DevicePlatform;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  pushToken?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  locale?: string;

  @ApiPropertyOptional({ description: "Décalage UTC en minutes (ex. 120 = UTC+2), pour les heures calmes (docs/03 §6)" })
  @IsOptional()
  @IsInt()
  @Min(-720)
  @Max(840)
  utcOffsetMinutes?: number;
}

export class DeviceDto {
  @ApiProperty() id!: string;
  @ApiProperty() platform!: string;
  @ApiProperty({ nullable: true, type: String }) pushToken!: string | null;
  @ApiProperty({ nullable: true, type: String }) locale!: string | null;
  @ApiProperty({ nullable: true, type: Number }) utcOffsetMinutes!: number | null;
}
