import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Job } from "bullmq";
import { QUEUE_NAME } from "./constants";
import { IngestionHeartbeatService } from "./heartbeat.service";
import { IngestionService } from "./ingestion.service";

@Processor(QUEUE_NAME)
export class IngestionProcessor extends WorkerHost {
  constructor(
    private readonly ingestion: IngestionService,
    private readonly heartbeat: IngestionHeartbeatService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    switch (job.name) {
      case "catalogue":
        await this.ingestion.runCatalogue();
        break;
      case "calendar":
        await this.ingestion.runCalendar();
        break;
      case "live":
        await this.ingestion.runLive();
        break;
      case "structure":
        await this.ingestion.runStructure();
        break;
      default:
        throw new Error(`Job d'ingestion inconnu : ${job.name}`);
    }
    // Marque le poll comme réussi même si rien n'a changé côté fournisseur
    // (provider_ref.last_synced_at, lui, ne bouge que si un payload change).
    await this.heartbeat.touch();
  }
}
