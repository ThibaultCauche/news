import { Module } from "@nestjs/common";
import { DbModule } from "../db/db.module";
import { PredictionSettlementService } from "./prediction-settlement.service";

@Module({
  imports: [DbModule],
  providers: [PredictionSettlementService],
})
export class PredictionsModule {}
