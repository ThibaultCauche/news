import { Processor, WorkerHost } from "@nestjs/bullmq";
import { AlertsService } from "./alerts.service";
import { ALERTS_QUEUE_NAME } from "./constants";

@Processor(ALERTS_QUEUE_NAME)
export class AlertsProcessor extends WorkerHost {
  constructor(private readonly alerts: AlertsService) {
    super();
  }

  async process(): Promise<void> {
    await this.alerts.check();
  }
}
