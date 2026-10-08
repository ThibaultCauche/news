import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { PoliticsController } from "./politics.controller";
import { PoliticsService } from "./politics.service";
import { QuizService } from "./quiz.service";

@Module({
  imports: [DbModule, CacheModule, AuthModule],
  controllers: [PoliticsController],
  providers: [PoliticsService, QuizService],
})
export class PoliticsModule {}
