import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient, UserSetting } from "@news/db";
import { PRISMA } from "../db/db.module";
import { UpdateUserSettingDto, UserSettingDto } from "./user-setting.dto";

function toUserSettingDto(setting: UserSetting): UserSettingDto {
  return {
    spoilerFree: setting.spoilerFree,
    morningDigest: setting.morningDigest,
    quietHoursStart: setting.quietHoursStart,
    quietHoursEnd: setting.quietHoursEnd,
  };
}

// `UserSetting` est créé en même temps que le compte (`AuthService.createAnonymousUser`) :
// pas d'upsert défensif ici, la ligne existe toujours.
@Injectable()
export class MeService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async getSettings(userId: string): Promise<UserSettingDto> {
    const setting = await this.prisma.userSetting.findUniqueOrThrow({ where: { userId } });
    return toUserSettingDto(setting);
  }

  async updateSettings(userId: string, dto: UpdateUserSettingDto): Promise<UserSettingDto> {
    const setting = await this.prisma.userSetting.update({ where: { userId }, data: dto });
    return toUserSettingDto(setting);
  }

  // RGPD (`DELETE /v1/me`, règle 9 de CLAUDE.md) : suppression en cascade des
  // appareils, abonnements, réglages et journal de notifications (schéma Prisma).
  async deleteAccount(userId: string): Promise<void> {
    await this.prisma.appUser.delete({ where: { id: userId } });
  }
}
