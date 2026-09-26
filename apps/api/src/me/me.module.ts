import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { MeController } from "./me.controller";
import { MeService } from "./me.service";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [MeController],
  providers: [MeService],
})
export class MeModule {}
