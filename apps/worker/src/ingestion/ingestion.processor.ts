import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Job } from "bullmq";
import { QUEUE_NAME } from "./constants";
import { IngestionService } from "./ingestion.service";

@Processor(QUEUE_NAME)
export class IngestionProcessor extends WorkerHost {
  constructor(private readonly ingestion: IngestionService) {
    super();
  }

  async process(job: Job): Promise<void> {
    switch (job.name) {
      case "catalogue":
        return this.ingestion.runCatalogue();
      case "calendar":
        return this.ingestion.runCalendar();
      case "live":
        return this.ingestion.runLive();
      case "structure":
        return this.ingestion.runStructure();
      default:
        throw new Error(`Job d'ingestion inconnu : ${job.name}`);
    }
  }
}
