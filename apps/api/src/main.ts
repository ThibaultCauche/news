import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { createLogger } from "@news/domain";
import { AppModule } from "./app.module";

const logger = createLogger("api");

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const port = process.env.PORT ?? 3000;
  await app.listen(port);
  logger.info({ port }, "api démarrée");
}

bootstrap().catch((err) => {
  logger.error(err, "échec au démarrage de l'api");
  process.exit(1);
});
