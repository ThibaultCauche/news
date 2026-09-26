import { Body, Controller, Put, UseGuards } from "@nestjs/common";
import { ApiOkResponse } from "@nestjs/swagger";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { DeviceDto, PutDeviceDto } from "./device.dto";
import { DevicesService } from "./devices.service";

// PUT /v1/devices/me — au lancement puis à chaque changement de jeton push
// (docs/03 §4).
@Controller("devices")
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Put("me")
  @ApiOkResponse({ type: DeviceDto })
  async putMe(@CurrentUser() user: AuthUser, @Body() dto: PutDeviceDto): Promise<DeviceDto> {
    return this.devices.upsert(user.id, dto);
  }
}
