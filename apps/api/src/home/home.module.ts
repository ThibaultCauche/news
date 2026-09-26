import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { SubscriptionsModule } from "../subscriptions/subscriptions.module";
import { HomeController } from "./home.controller";
import { HomeService } from "./home.service";

@Module({
  imports: [DbModule, CacheModule, AuthModule, SubscriptionsModule],
  controllers: [HomeController],
  providers: [HomeService],
})
export class HomeModule {}
