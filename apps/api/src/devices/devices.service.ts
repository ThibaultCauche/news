import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { PRISMA } from "../db/db.module";
import { DeviceDto, PutDeviceDto } from "./device.dto";

@Injectable()
export class DevicesService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async upsert(userId: string, dto: PutDeviceDto): Promise<DeviceDto> {
    const data = {
      pushToken: dto.pushToken ?? null,
      platform: dto.platform,
      locale: dto.locale ?? null,
      utcOffsetMinutes: dto.utcOffsetMinutes ?? null,
    };
    const device = await this.prisma.device.upsert({
      where: { userId_installId: { userId, installId: dto.installId } },
      create: { id: randomUUID(), userId, installId: dto.installId, ...data },
      update: data,
    });
    return {
      id: device.id,
      platform: device.platform,
      pushToken: device.pushToken,
      locale: device.locale,
      utcOffsetMinutes: device.utcOffsetMinutes,
    };
  }
}
