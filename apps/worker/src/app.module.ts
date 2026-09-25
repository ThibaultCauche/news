import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import Redis from "ioredis";
import { IngestionModule } from "./ingestion/ingestion.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: new Redis(config.getOrThrow<string>("REDIS_URL"), { maxRetriesPerRequest: null }),
      }),
    }),
    IngestionModule,
  ],
})
export class AppModule {}
