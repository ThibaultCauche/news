import "./instrument";
import "reflect-metadata";
import { writeFileSync } from "node:fs";
import { ValidationPipe } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import * as Sentry from "@sentry/nestjs";
import express from "express";
import { createLogger } from "@news/domain";
import { AppModule } from "./app.module";

const logger = createLogger("api");

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix("v1", { exclude: ["health"] });
  // CORS reste fermé par défaut (règle 9 de CLAUDE.md, l'appli mobile n'en a
  // pas besoin) ; n'active une origine que pour vérifier l'appli Flutter web
  // en local, jamais en prod (`CORS_DEV_ORIGIN` n'est jamais défini ailleurs).
  if (process.env.CORS_DEV_ORIGIN) app.enableCors();
  app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true }));

  const document = SwaggerModule.createDocument(
    app,
    new DocumentBuilder().setTitle("News API").setDescription("API consommée par l'appli Flutter (docs/03 §4)").setVersion("1").build(),
  );

  // `pnpm generate:openapi` : écrit la spec et sort, sans écouter de port
  // (docs/04 J2 : "client Dart généré depuis OpenAPI").
  const writeSpecPath = process.argv.find((arg) => arg.startsWith("--write-openapi="))?.split("=")[1];
  if (writeSpecPath) {
    writeFileSync(writeSpecPath, JSON.stringify(document, null, 2));
    logger.info({ path: writeSpecPath }, "spec OpenAPI écrite");
    await app.close();
    return;
  }

  const port = process.env.PORT ?? 3000;

  // Derrière Tailscale Funnel, l'API cohabite avec d'autres services sur le
  // même port public : montée sous un chemin (ex. "news"), non un port dédié
  // (docs/05-deploiement.md §3). Express ne retire pas ce préfixe lui-même,
  // donc on le fait ici en montant l'appli Nest sous une appli Express externe
  // (`GET /v1/home` en local devient `GET /news/v1/home` en prod).
  const pathPrefix = process.env.PUBLIC_PATH_PREFIX;
  if (pathPrefix) {
    const outer = express();
    outer.use(`/${pathPrefix}`, app.getHttpAdapter().getInstance());
    await app.init();
    outer.listen(port);
    logger.info({ port, pathPrefix }, "api démarrée");
  } else {
    await app.listen(port);
    logger.info({ port }, "api démarrée");
  }
}

bootstrap().catch((err) => {
  logger.error(err, "échec au démarrage de l'api");
  Sentry.captureException(err);
  process.exit(1);
});
