import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { HomeController } from "./home.controller";
import { HomeService } from "./home.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [HomeController],
  providers: [HomeService],
})
export class HomeModule {}
