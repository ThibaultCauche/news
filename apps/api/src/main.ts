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
import { trustProxyHops } from "./proxy";

const logger = createLogger("api");

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix("v1", { exclude: ["health"] });
  trustProxyHops(app);
  // CORS reste fermé par défaut (règle 9 de CLAUDE.md, l'appli mobile n'en a
  // pas besoin) ; n'active une origine que pour vérifier l'appli Flutter web
  // en local, jamais en prod (`CORS_DEV_ORIGIN` n'est jamais défini ailleurs).
  if (process.env.CORS_DEV_ORIGIN) app.enableCors();
  // Version web (J17) : le build `flutter build web` est servi par l'API elle-même (même origine, donc pas de CORS).
  // Hors `/v1` et `/health` ; ponytail: pas de repli sur index.html, l'appli n'utilise pas d'URL de page.
  if (process.env.WEB_DIR) app.use(express.static(process.env.WEB_DIR));
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

  // Tailscale Funnel (utilisé en prod, docs/05-deploiement.md §3) retire déjà
  // le préfixe de chemin avant de relayer vers l'API : PUBLIC_PATH_PREFIX y
  // reste vide. Cet interrupteur ne sert que derrière un reverse proxy qui,
  // lui, ne retire pas le préfixe (`GET /v1/home` en local deviendrait alors
  // `GET /<préfixe>/v1/home` côté public).
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
