import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "./app.module";
import { trustProxyHops } from "./proxy";

// Limite de 3 requêtes pour voir le compteur bouger vite : `GET /health` est limité comme le reste.
async function appWithLimit(hops: number): Promise<INestApplication> {
  process.env.THROTTLE_LIMIT = "3";
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix("v1", { exclude: ["health"] });
  trustProxyHops(app, hops);
  await app.init();
  return app;
}

const hit = (app: INestApplication, forwardedFor: string) => request(app.getHttpServer()).get("/health").set("X-Forwarded-For", forwardedFor);

describe("limite de requêtes derrière un relais (e2e)", () => {
  it("sans relais de confiance, tous les clients partagent le même compteur", async () => {
    const app = await appWithLimit(0);
    try {
      for (let i = 0; i < 3; i++) await hit(app, `10.0.0.${i}`).expect(200);
      await hit(app, "10.0.0.99").expect(429);
    } finally {
      await app.close();
    }
  });

  it("avec un relais de confiance, chaque client a son compteur, et une valeur ajoutée à gauche n'en crée pas un nouveau", async () => {
    const app = await appWithLimit(1);
    try {
      for (let i = 0; i < 3; i++) await hit(app, "203.0.113.1").expect(200);
      await hit(app, "203.0.113.1").expect(429);
      await hit(app, "203.0.113.2").expect(200);
      await hit(app, "198.51.100.7, 203.0.113.1").expect(429);
    } finally {
      await app.close();
    }
  });
});
