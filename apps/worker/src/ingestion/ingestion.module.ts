import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { AssembleeProvider, ElectionsProvider, JolpicaProvider, PandaScoreProvider, StartGgProvider } from "@news/providers";
import { ASSEMBLEE_PROVIDER, AssembleeModule } from "../assemblee/assemblee.module";
import { DbModule } from "../db/db.module";
import { ELECTIONS_PROVIDER, ElectionsModule } from "../elections/elections.module";
import { EventBusModule } from "../events/event-bus.module";
import { JOLPICA_PROVIDER, JolpicaModule } from "../jolpica/jolpica.module";
import { PANDASCORE_PROVIDER, PandaScoreModule } from "../pandascore/pandascore.module";
import { STARTGG_PROVIDER, StartGgModule } from "../startgg/startgg.module";
import { QUEUE_NAME } from "./constants";
import { IngestionHeartbeatService } from "./heartbeat.service";
import { IngestionProcessor } from "./ingestion.processor";
import { IngestionScheduler } from "./ingestion.scheduler";
import { IngestionService } from "./ingestion.service";
import { INGESTION_PROVIDERS, IngestionProviders } from "./providers";

@Module({
  imports: [DbModule, PandaScoreModule, StartGgModule, JolpicaModule, AssembleeModule, ElectionsModule, EventBusModule, BullModule.registerQueue({ name: QUEUE_NAME })],
  providers: [
    {
      provide: INGESTION_PROVIDERS,
      useFactory: (pandascore: PandaScoreProvider, startgg: StartGgProvider | null, jolpica: JolpicaProvider, assemblee: AssembleeProvider, elections: ElectionsProvider): IngestionProviders => ({
        pandascore,
        ...(startgg ? { startgg } : {}),
        jolpica,
        assemblee,
        elections,
      }),
      inject: [PANDASCORE_PROVIDER, STARTGG_PROVIDER, JOLPICA_PROVIDER, ASSEMBLEE_PROVIDER, ELECTIONS_PROVIDER],
    },
    IngestionService,
    IngestionProcessor,
    IngestionScheduler,
    IngestionHeartbeatService,
  ],
  exports: [IngestionHeartbeatService],
})
export class IngestionModule {}
