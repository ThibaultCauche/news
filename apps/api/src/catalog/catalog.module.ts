import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { CatalogController } from "./catalog.controller";
import { CatalogService } from "./catalog.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [CatalogController],
  providers: [CatalogService],
})
export class CatalogModule {}
