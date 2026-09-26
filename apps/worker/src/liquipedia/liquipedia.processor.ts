import { Processor, WorkerHost } from "@nestjs/bullmq";
import { LIQUIPEDIA_QUEUE_NAME } from "./constants";
import { LiquipediaContextService } from "./liquipedia-context.service";

@Processor(LIQUIPEDIA_QUEUE_NAME)
export class LiquipediaProcessor extends WorkerHost {
  constructor(private readonly context: LiquipediaContextService) {
    super();
  }

  async process(): Promise<void> {
    return this.context.run();
  }
}
