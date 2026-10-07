import { Processor, WorkerHost } from "@nestjs/bullmq";
import { STARTING_SOON_QUEUE_NAME } from "./starting-soon.constants";
import { MorningDigestService } from "./morning-digest.service";
import { PickemReminderService } from "./pickem-reminder.service";
import { StartingSoonService } from "./starting-soon.service";

@Processor(STARTING_SOON_QUEUE_NAME)
export class StartingSoonProcessor extends WorkerHost {
  constructor(
    private readonly startingSoon: StartingSoonService,
    private readonly morningDigest: MorningDigestService,
    private readonly pickemReminder: PickemReminderService,
  ) {
    super();
  }

  async process(): Promise<void> {
    await this.startingSoon.run();
    await this.morningDigest.run();
    await this.pickemReminder.run();
  }
}
