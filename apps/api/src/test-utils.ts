import { randomUUID } from "node:crypto";
import { INestApplication, UnauthorizedException, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "./app.module";
import { FirebaseAuthService, FirebaseIdentity } from "./auth/firebase-auth.service";

// Faux Firebase pour les e2e : le « ID token » est `test:<uid>:<verified>` (pas de réseau,
// pas de vrai projet Firebase). `deletedUids` permet de vérifier la suppression RGPD.
export class FakeFirebaseAuthService {
  static deletedUids: string[] = [];

  async verifyIdToken(idToken: string): Promise<FirebaseIdentity> {
    const [prefix, uid, verified] = idToken.split(":");
    if (prefix !== "test" || !uid) throw new UnauthorizedException("jeton de test invalide");
    return { uid, emailVerified: verified === "true" };
  }

  async deleteUser(uid: string): Promise<void> {
    FakeFirebaseAuthService.deletedUids.push(uid);
  }
}

export async function createTestApp(): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(FirebaseAuthService)
    .useClass(FakeFirebaseAuthService)
    .compile();
  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix("v1", { exclude: ["health"] });
  app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true }));
  await app.init();
  return app;
}

// Comptes créés par `loginTestUser` : supprimés en fin de suite (`deleteTestUsers`), sinon ils
// s'accumulent dans la base de dev (et leurs groupes avec eux).
const createdUserIds: string[] = [];

/** À appeler dans `afterAll`, avant `prisma.$disconnect()`. */
export async function deleteTestUsers(prisma: { appUser: { deleteMany: (args: { where: { id: { in: string[] } } }) => Promise<unknown> } }): Promise<void> {
  await prisma.appUser.deleteMany({ where: { id: { in: createdUserIds.splice(0) } } });
}

export interface TestAccount {
  userId: string;
  accessToken: string;
  refreshToken: string;
  uid: string;
  auth: { Authorization: string };
}

/** Compte connecté via le faux Firebase (e-mail vérifié par défaut). */
export async function loginTestUser(app: INestApplication, options: { uid?: string; verified?: boolean } = {}): Promise<TestAccount> {
  const uid = options.uid ?? randomUUID();
  const res = await request(app.getHttpServer())
    .post("/v1/auth/firebase")
    .send({ idToken: `test:${uid}:${options.verified ?? true}` })
    .expect(201);
  const body = res.body as { userId: string; accessToken: string; refreshToken: string };
  createdUserIds.push(body.userId);
  return { ...body, uid, auth: { Authorization: `Bearer ${body.accessToken}` } };
}
