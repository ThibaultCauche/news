import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, OnModuleInit } from "@nestjs/common";
import { Queue } from "bullmq";
import { JOB_INTERVALS_MS, QUEUE_NAME } from "./constants";

// Programme les jobs répétés et déclenche un premier passage immédiat de
// chacun, pour ne pas attendre 6h avant de voir les premières données.
@Injectable()
export class IngestionScheduler implements OnModuleInit {
  constructor(@InjectQueue(QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    for (const [name, every] of Object.entries(JOB_INTERVALS_MS)) {
      await this.queue.add(name, {}, { repeat: { every }, jobId: name });
      await this.queue.add(name, {});
    }
  }
}
