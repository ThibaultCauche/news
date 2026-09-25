import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PandaScoreClient, PandaScoreProvider } from "@news/providers";

export const PANDASCORE_PROVIDER = "PANDASCORE_PROVIDER";

@Module({
  providers: [
    {
      provide: PANDASCORE_PROVIDER,
      useFactory: (config: ConfigService) => {
        const token = config.getOrThrow<string>("PANDASCORE_TOKEN");
        return new PandaScoreProvider(new PandaScoreClient(token));
      },
      inject: [ConfigService],
    },
  ],
  exports: [PANDASCORE_PROVIDER],
})
export class PandaScoreModule {}
