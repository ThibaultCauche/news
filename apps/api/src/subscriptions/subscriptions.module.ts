import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { SubscriptionsController } from "./subscriptions.controller";
import { SubscriptionsService } from "./subscriptions.service";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [SubscriptionsController],
  providers: [SubscriptionsService],
  exports: [SubscriptionsService],
})
export class SubscriptionsModule {}
