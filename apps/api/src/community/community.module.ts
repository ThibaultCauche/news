import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { CommunityController } from "./community.controller";
import { CommunityService } from "./community.service";
import { StagePickService } from "./stage-pick.service";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [CommunityController],
  providers: [CommunityService, StagePickService],
})
export class CommunityModule {}
