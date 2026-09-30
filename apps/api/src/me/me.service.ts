import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient, UserSetting } from "@news/db";
import { FirebaseAuthService } from "../auth/firebase-auth.service";
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

// `UserSetting` est créé en même temps que le compte (`AuthService.loginWithFirebase`) :
// pas d'upsert défensif ici, la ligne existe toujours.
@Injectable()
export class MeService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly firebase: FirebaseAuthService,
  ) {}

  async getSettings(userId: string): Promise<UserSettingDto> {
    const setting = await this.prisma.userSetting.findUniqueOrThrow({ where: { userId } });
    return toUserSettingDto(setting);
  }

  async updateSettings(userId: string, dto: UpdateUserSettingDto): Promise<UserSettingDto> {
    const setting = await this.prisma.userSetting.update({ where: { userId }, data: dto });
    return toUserSettingDto(setting);
  }

  // RGPD (`DELETE /v1/me`, règle 9 de CLAUDE.md) : suppression en cascade des appareils,
  // abonnements, réglages, journal de notifications, pronostics et groupes (schéma Prisma),
  // puis du compte Firebase (e-mail et mot de passe).
  async deleteAccount(userId: string): Promise<void> {
    const user = await this.prisma.appUser.findUnique({ where: { id: userId }, select: { firebaseUid: true } });
    if (user?.firebaseUid) await this.firebase.deleteUser(user.firebaseUid);
    await this.prisma.appUser.delete({ where: { id: userId } });
  }
}
