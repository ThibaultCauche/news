import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, OnModuleInit } from "@nestjs/common";
import { Queue } from "bullmq";
import { STARTING_SOON_INTERVAL_MS, STARTING_SOON_QUEUE_NAME } from "./starting-soon.constants";

@Injectable()
export class StartingSoonScheduler implements OnModuleInit {
  constructor(@InjectQueue(STARTING_SOON_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.add("check", {}, { repeat: { every: STARTING_SOON_INTERVAL_MS }, jobId: "check" });
  }
}
