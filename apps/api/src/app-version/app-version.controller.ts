import { Controller, Get } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ApiOkResponse, ApiProperty } from "@nestjs/swagger";

export class AppVersionDto {
  /** Dernière version publiée : sous cette version, l'appli propose de se mettre à jour. */
  @ApiProperty() latest!: string;
  /** Version minimale : en dessous, l'appli bloque jusqu'à la mise à jour. */
  @ApiProperty() minSupported!: string;
  @ApiProperty({ nullable: true, type: String }) notes!: string | null;
}

// GET /v1/app/version — vérification de version au lancement (J21). Lu dans `.env`, donc un
// changement ne demande qu'un redémarrage de l'API, pas une nouvelle version de l'appli.
@Controller("app")
export class AppVersionController {
  constructor(private readonly config: ConfigService) {}

  @Get("version")
  @ApiOkResponse({ type: AppVersionDto })
  get(): AppVersionDto {
    return {
      latest: this.config.get<string>("APP_LATEST_VERSION") || "1.0.0",
      minSupported: this.config.get<string>("APP_MIN_SUPPORTED_VERSION") || "1.0.0",
      notes: this.config.get<string>("APP_UPDATE_NOTES") || null,
    };
  }
}
