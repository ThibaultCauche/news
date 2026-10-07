import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { ForumController, ModerationController } from "./forum.controller";
import { ForumService } from "./forum.service";
import { InboxService } from "./inbox.service";
import { ModerationService } from "./moderation.service";

@Module({
  imports: [DbModule, AuthModule, CacheModule],
  controllers: [ForumController, ModerationController],
  providers: [ForumService, InboxService, ModerationService],
})
export class ForumModule {}
