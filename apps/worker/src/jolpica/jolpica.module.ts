import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JolpicaClient, JolpicaProvider } from "@news/providers";

export const JOLPICA_PROVIDER = "JOLPICA_PROVIDER";

// Jolpica-F1 n'a pas de clé : la F1 est toujours ingérée. Le contact de `LIQUIPEDIA_USER_AGENT` sert d'identifiant.
@Module({
  providers: [
    {
      provide: JOLPICA_PROVIDER,
      useFactory: (config: ConfigService) => new JolpicaProvider(new JolpicaClient(config.get<string>("LIQUIPEDIA_USER_AGENT") ?? "Keryx")),
      inject: [ConfigService],
    },
  ],
  exports: [JOLPICA_PROVIDER],
})
export class JolpicaModule {}
