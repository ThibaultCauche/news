import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { LearnService } from "./learn.service";
import { MeController } from "./me.controller";
import { MeService } from "./me.service";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [MeController],
  providers: [MeService, LearnService],
})
export class MeModule {}
