import { Inject, Module, OnModuleDestroy } from "@nestjs/common";
import { createPrismaClient, PrismaClient } from "@news/db";

export const PRISMA = "PRISMA";

@Module({
  providers: [{ provide: PRISMA, useFactory: () => createPrismaClient() }],
  exports: [PRISMA],
})
export class DbModule implements OnModuleDestroy {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async onModuleDestroy() {
    await this.prisma.$disconnect();
  }
}
