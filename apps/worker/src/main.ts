import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { createLogger } from "@news/domain";
import { AppModule } from "./app.module";

const logger = createLogger("worker");

async function bootstrap() {
  await NestFactory.createApplicationContext(AppModule);
  logger.info("worker démarré");
}

bootstrap().catch((err) => {
  logger.error(err, "échec au démarrage du worker");
  process.exit(1);
});
