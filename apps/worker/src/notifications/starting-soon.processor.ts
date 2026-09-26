import { Processor, WorkerHost } from "@nestjs/bullmq";
import { STARTING_SOON_QUEUE_NAME } from "./starting-soon.constants";
import { StartingSoonService } from "./starting-soon.service";

@Processor(STARTING_SOON_QUEUE_NAME)
export class StartingSoonProcessor extends WorkerHost {
  constructor(private readonly startingSoon: StartingSoonService) {
    super();
  }

  async process(): Promise<void> {
    await this.startingSoon.run();
  }
}
