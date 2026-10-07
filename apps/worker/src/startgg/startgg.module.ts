import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { createLogger } from "@news/domain";
import { StartGgClient, StartGgProvider } from "@news/providers";

export const STARTGG_PROVIDER = "STARTGG_PROVIDER";

const logger = createLogger("worker:startgg");

// Sans `STARTGG_TOKEN`, Smash Ultimate n'est pas ingéré (le reste fonctionne) : le fournisseur vaut `null`.
@Module({
  providers: [
    {
      provide: STARTGG_PROVIDER,
      useFactory: (config: ConfigService) => {
        const token = config.get<string>("STARTGG_TOKEN");
        if (!token) {
          logger.warn("STARTGG_TOKEN absent : Smash Ultimate (start.gg) n'est pas ingéré");
          return null;
        }
        return new StartGgProvider(new StartGgClient(token));
      },
      inject: [ConfigService],
    },
  ],
  exports: [STARTGG_PROVIDER],
})
export class StartGgModule {}
