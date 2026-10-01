import { Processor, WorkerHost } from "@nestjs/bullmq";
import { STARTING_SOON_QUEUE_NAME } from "./starting-soon.constants";
import { PredictionReminderService } from "./prediction-reminder.service";
import { StartingSoonService } from "./starting-soon.service";

@Processor(STARTING_SOON_QUEUE_NAME)
export class StartingSoonProcessor extends WorkerHost {
  constructor(
    private readonly startingSoon: StartingSoonService,
    private readonly predictionReminder: PredictionReminderService,
  ) {
    super();
  }

  async process(): Promise<void> {
    await this.startingSoon.run();
    await this.predictionReminder.run();
  }
}
