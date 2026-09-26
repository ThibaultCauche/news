import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { DevicesController } from "./devices.controller";
import { DevicesService } from "./devices.service";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [DevicesController],
  providers: [DevicesService],
})
export class DevicesModule {}
