import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, OnModuleInit } from "@nestjs/common";
import { Queue } from "bullmq";
import { ALERTS_CHECK_INTERVAL_MS, ALERTS_QUEUE_NAME } from "./constants";

@Injectable()
export class AlertsScheduler implements OnModuleInit {
  constructor(@InjectQueue(ALERTS_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.add("check", {}, { repeat: { every: ALERTS_CHECK_INTERVAL_MS }, jobId: "check" });
  }
}
