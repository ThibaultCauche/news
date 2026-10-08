import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ElectionsClient, ElectionsProvider } from "@news/providers";

export const ELECTIONS_PROVIDER = "ELECTIONS_PROVIDER";

// Les résultats viennent de data.gouv.fr (ministère de l'Intérieur), sans clé : les élections sont toujours ingérées.
@Module({
  providers: [
    {
      provide: ELECTIONS_PROVIDER,
      useFactory: (config: ConfigService) => new ElectionsProvider(new ElectionsClient(config.get<string>("LIQUIPEDIA_USER_AGENT") ?? "Keryx")),
      inject: [ConfigService],
    },
  ],
  exports: [ELECTIONS_PROVIDER],
})
export class ElectionsModule {}
