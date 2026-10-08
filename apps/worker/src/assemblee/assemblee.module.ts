import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AssembleeClient, AssembleeProvider } from "@news/providers";

export const ASSEMBLEE_PROVIDER = "ASSEMBLEE_PROVIDER";

// L'open data de l'Assemblée n'a pas de clé : la politique est toujours ingérée. Le contact de
// `LIQUIPEDIA_USER_AGENT` sert d'identifiant, comme pour Jolpica.
@Module({
  providers: [
    {
      provide: ASSEMBLEE_PROVIDER,
      useFactory: (config: ConfigService) => new AssembleeProvider(new AssembleeClient(config.get<string>("LIQUIPEDIA_USER_AGENT") ?? "Keryx")),
      inject: [ConfigService],
    },
  ],
  exports: [ASSEMBLEE_PROVIDER],
})
export class AssembleeModule {}
